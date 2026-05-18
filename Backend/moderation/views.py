from decimal import Decimal

from django.db import IntegrityError, transaction
from django.shortcuts import get_object_or_404
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework import status

from trips.models import Trip, TripParticipant

from .models import TrustScoreLog, Report, Review
from .services import TrustScoreUpdateError, update_trust_score


def _peer_rating_to_raw_delta(rating: int) -> Decimal:
    return {
        5: Decimal("1.0"),
        4: Decimal("0.5"),
        3: Decimal("0.0"),
        2: Decimal("-0.5"),
        1: Decimal("-1.0"),
    }.get(rating, Decimal("0.0"))

class TrustScoreLogView(APIView):
    permission_classes = [IsAuthenticated]
    def get(self, request):
        logs = TrustScoreLog.objects.filter(user=request.user).order_by('-created_at')
        log_data = []
        for log in logs:
            if log.applied_delta > 0:
                applied_delta_str = f"+{log.applied_delta}"
            else:
                applied_delta_str = f"{log.applied_delta}"
            log_data.append({
                "event_type": log.event_type,
                "direction": log.direction,
                "applied_delta": applied_delta_str,
                "reason_detail": log.reason_detail,
                "score_after": log.score_after,
                "created_at": log.created_at.isoformat(),
            })
        return Response(log_data, status=status.HTTP_200_OK)

class ReportUserView(APIView):
    permission_classes = [IsAuthenticated]
    def post(self, request):
        Report.objects.create(
            reporter_user=request.user,
            reported_user_id=request.data.get('target_id'),
            trip_id=request.data.get('trip_id'),
            reason=request.data.get('reason'),
            detail=request.data.get('detail'),
            status='PENDING'
        )
        return Response({"message": "Report submitted successfully"}, status=status.HTTP_201_CREATED)


class TripReviewCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        trip_id = request.data.get("trip_id")
        reviews_data = request.data.get("reviews")

        if trip_id is None:
            return Response(
                {"detail": "trip_id가 필요합니다."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            trip_id_int = int(trip_id)
        except (TypeError, ValueError):
            return Response(
                {"detail": "trip_id는 정수여야 합니다."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if not isinstance(reviews_data, list):
            return Response(
                {"detail": "reviews는 배열이어야 합니다."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        trip = get_object_or_404(Trip, pk=trip_id_int)

        joined_ids = set(
            TripParticipant.objects.filter(
                trip=trip,
                status=TripParticipant.StatusChoices.JOINED,
            ).values_list("user_id", flat=True)
        )

        if request.user.id not in joined_ids:
            return Response(
                {"detail": "해당 트립에 참여 중인 사용자만 평가할 수 있습니다."},
                status=status.HTTP_403_FORBIDDEN,
            )

        if len(reviews_data) == 0:
            return Response(
                {"message": "평가 항목이 없습니다.", "created": 0},
                status=status.HTTP_200_OK,
            )

        parsed = []

        for item in reviews_data:
            if not isinstance(item, dict):
                return Response(
                    {"detail": "reviews의 각 항목은 객체여야 합니다."},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            to_user_id = item.get("to_user_id")
            rating = item.get("rating")

            try:
                to_user_id_int = int(to_user_id)
                rating_int = int(rating)
            except (TypeError, ValueError):
                return Response(
                    {"detail": "to_user_id와 rating은 정수여야 합니다."},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            if rating_int < 1 or rating_int > 5:
                return Response(
                    {"detail": "rating은 1~5 사이여야 합니다."},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            if to_user_id_int == request.user.id:
                return Response(
                    {"detail": "본인에게는 평가할 수 없습니다."},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            if to_user_id_int not in joined_ids:
                return Response(
                    {"detail": f"트립 참여자가 아닌 사용자(to_user_id={to_user_id_int})입니다."},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            parsed.append((to_user_id_int, rating_int))

        seen_to = set()
        for to_user_id_int, _rating_int in parsed:
            if to_user_id_int in seen_to:
                return Response(
                    {"detail": "reviews에 동일한 to_user_id가 중복되었습니다."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            seen_to.add(to_user_id_int)

        created_reviews = []

        try:
            with transaction.atomic():
                for to_user_id_int, rating_int in parsed:
                    review = Review.objects.create(
                        trip=trip,
                        from_user=request.user,
                        to_user_id=to_user_id_int,
                        rating=rating_int,
                    )

                    raw_delta = _peer_rating_to_raw_delta(rating_int)

                    result = update_trust_score(
                        user_id=to_user_id_int,
                        event_type="MANUAL_ADJUST",
                        raw_base_score=raw_delta,
                        reason_detail=f"동승 상호 평가 (별점 {rating_int})",
                        related_trip_id=trip.id,
                        created_by_system=False,
                        actor_user_id=request.user.id,
                    )

                    TrustScoreLog.objects.filter(pk=result.log_id).update(
                        related_review_id=review.id,
                    )

                    created_reviews.append(review.id)

        except IntegrityError:
            return Response(
                {"detail": "이미 해당 트립에 대해 이 사용자에게 평가를 남겼습니다."},
                status=status.HTTP_409_CONFLICT,
            )
        except TrustScoreUpdateError as exc:
            return Response(
                {"detail": str(exc)},
                status=status.HTTP_400_BAD_REQUEST,
            )

        return Response(
            {
                "message": "평가가 저장되었습니다.",
                "created": len(created_reviews),
                "review_ids": created_reviews,
            },
            status=status.HTTP_201_CREATED,
        )