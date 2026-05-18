from django.shortcuts import get_object_or_404
from rest_framework import generics, status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.parsers import MultiPartParser, FormParser

from trips.models import Trip

from .models import PaymentChannel, Receipt, Settlement
from .serializers import (
    PaymentChannelSerializer,
    PaymentChannelUpsertSerializer,
    ReceiptSerializer,
    ReceiptCreateSerializer,
    ReceiptOCRResultSerializer,
    ReceiptConfirmAmountSerializer,
    SettlementSerializer,
    SettlementProofSerializer,
    SettlementProofCreateSerializer,
)
from .services import (
    upsert_payment_channel,
    create_receipt,
    analyze_receipt_ocr,
    confirm_receipt_amount,
    create_settlements_for_receipt,
    mark_settlement_link_opened,
    mark_settlement_paid_self,
    upload_settlement_proof,
    confirm_settlement,
    dispute_settlement,
    complete_trip_settlement,
)


class TripPaymentChannelUpsertView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, trip_id):
        trip = get_object_or_404(Trip, id=trip_id)

        serializer = PaymentChannelUpsertSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        channel = upsert_payment_channel(
            trip=trip,
            user=request.user,
            validated_data=serializer.validated_data,
        )
        return Response(
            PaymentChannelSerializer(channel, context={"request": request}).data,
            status=status.HTTP_200_OK,
        )


class TripPaymentChannelDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, trip_id):
        trip = get_object_or_404(Trip, id=trip_id)
        channel = get_object_or_404(PaymentChannel, trip=trip)
        return Response(
            PaymentChannelSerializer(channel, context={"request": request}).data,
            status=status.HTTP_200_OK,
        )

class TripReceiptCreateView(APIView):
    permission_classes = [IsAuthenticated]
    parser_classes = (MultiPartParser, FormParser)

    def post(self, request, trip_id):
        trip = get_object_or_404(Trip, id=trip_id)

        serializer = ReceiptCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        receipt = create_receipt(
            trip=trip,
            user=request.user,
            validated_data=serializer.validated_data,
        )

        return Response(
            ReceiptSerializer(receipt, context={"request": request}).data,
            status=status.HTTP_201_CREATED,
        )


class TripReceiptDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, trip_id):
        trip = get_object_or_404(Trip, id=trip_id)
        receipt = get_object_or_404(Receipt, trip=trip)
        return Response(
            ReceiptSerializer(receipt, context={"request": request}).data,
            status=status.HTTP_200_OK,
        )
        
class ReceiptAnalyzeOCRView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, receipt_id):
        receipt = get_object_or_404(Receipt, id=receipt_id)

        receipt = analyze_receipt_ocr(
            receipt=receipt,
            actor=request.user,
        )

        return Response(
            ReceiptOCRResultSerializer(receipt, context={"request": request}).data,
            status=status.HTTP_200_OK,
        )
        
class ReceiptConfirmAmountView(APIView):
    permission_classes = [IsAuthenticated]

    def patch(self, request, receipt_id):
        receipt = get_object_or_404(Receipt, id=receipt_id)

        serializer = ReceiptConfirmAmountSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        receipt = confirm_receipt_amount(
            receipt=receipt,
            actor=request.user,
            total_amount=serializer.validated_data["total_amount"],
        )

        return Response(
            ReceiptSerializer(receipt, context={"request": request}).data,
            status=status.HTTP_200_OK,
        )

class TripSettlementCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, trip_id):
        trip = get_object_or_404(Trip, id=trip_id)
        receipt = get_object_or_404(Receipt, trip=trip)

        settlements = create_settlements_for_receipt(
            receipt=receipt,
            actor=request.user,
        )

        system_text = "정산 요청이 도착했습니다."

        try:
            from chat.models import ChatRoom, ChatMessage
            from asgiref.sync import async_to_sync
            from channels.layers import get_channel_layer

            room = ChatRoom.objects.filter(trip=trip).first()

            if room:
                system_message = ChatMessage.objects.create(
                    room=room,
                    sender_user=request.user,
                    message=system_text,
                    message_type=ChatMessage.MessageTypeChoices.SYSTEM,
                )

                channel_layer = get_channel_layer()

                if channel_layer:
                    first_settlement_data = SettlementSerializer(
                        settlements[0],
                        context={"request": request},
                    ).data if settlements else None

                    settlement_event = {
                        "type": "broadcast_message",
                        "message_type": "settlement_request",
                        "message": system_text,
                        "sender": request.user.username,
                        "sender_user_id": request.user.id,
                        "message_id": system_message.id,
                        "sent_at": system_message.sent_at.isoformat(),
                        "settlement": first_settlement_data,
                    }

                    async_to_sync(channel_layer.group_send)(
                        f"chat_{room.id}",
                        settlement_event,
                    )

                    if room.id != trip.id:
                        async_to_sync(channel_layer.group_send)(
                            f"chat_{trip.id}",
                            settlement_event,
                        )

                    user_ids = set()

                    if trip.leader_user_id:
                        user_ids.add(trip.leader_user_id)

                    joined_user_ids = trip.trip_participants.filter(
                        status="JOINED",
                    ).values_list("user_id", flat=True)

                    user_ids.update(joined_user_ids)
                    user_ids.discard(request.user.id)

                    for user_id in user_ids:
                        async_to_sync(channel_layer.group_send)(
                            f"user_{user_id}",
                            {
                                "type": "chat_room_updated",
                                "room_id": room.id,
                                "last_message": system_text,
                                "message_type": "SYSTEM",
                                "sender": request.user.username,
                                "sender_user_id": request.user.id,
                                "sent_at": system_message.sent_at.isoformat(),
                            },
                        )

        except Exception as e:
            print(f"[정산 요청 채팅 알림 오류] {e}")

        return Response(
            SettlementSerializer(
                settlements,
                many=True,
                context={"request": request},
            ).data,
            status=status.HTTP_201_CREATED,
        )

class TripSettlementCompleteView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, trip_id):
        trip = get_object_or_404(Trip, id=trip_id)

        result = complete_trip_settlement(
            trip=trip,
            user=request.user,
        )

        return Response(
            {
                "detail": "정산이 완료되었습니다.",
                "pinned_notice": result["pinned_notice"],
                "expires_at": result["expires_at"],
            },
            status=status.HTTP_200_OK,
        )


class TripSettlementListView(generics.ListAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = SettlementSerializer

    def get_queryset(self):
        trip_id = self.kwargs["trip_id"]
        return (
            Settlement.objects
            .filter(receipt__trip_id=trip_id)
            .select_related("receipt", "receipt__trip", "payer_user", "payee_user", "verified_by")
            .prefetch_related("proofs")
            .order_by("id")
        )


class MyPaySettlementListView(generics.ListAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = SettlementSerializer

    def get_queryset(self):
        return (
            Settlement.objects
            .filter(payer_user=self.request.user)
            .select_related("receipt", "receipt__trip", "payer_user", "payee_user", "verified_by")
            .prefetch_related("proofs")
            .order_by("-requested_at")
        )


class MyReceiveSettlementListView(generics.ListAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = SettlementSerializer

    def get_queryset(self):
        return (
            Settlement.objects
            .filter(payee_user=self.request.user)
            .select_related("receipt", "receipt__trip", "payer_user", "payee_user", "verified_by")
            .prefetch_related("proofs")
            .order_by("-requested_at")
        )

class SettlementDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, settlement_id):
        settlement = get_object_or_404(
            Settlement.objects.select_related(
                "trip",
                "receipt",
                "payer_user",
                "payee_user",
                "verified_by",
            ).prefetch_related("proofs"),
            id=settlement_id,
        )

        if request.user.id not in [settlement.payer_user_id, settlement.payee_user_id]:
            return Response(
                {"detail": "정산 당사자만 조회할 수 있습니다."},
                status=status.HTTP_403_FORBIDDEN,
            )

        return Response(
            SettlementSerializer(settlement, context={"request": request}).data,
            status=status.HTTP_200_OK,
        )

class SettlementLinkOpenView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, settlement_id):
        settlement = get_object_or_404(Settlement, id=settlement_id)

        settlement = mark_settlement_link_opened(
            settlement=settlement,
            user=request.user,
        )

        return Response(
            SettlementSerializer(settlement, context={"request": request}).data,
            status=status.HTTP_200_OK,
        )

class SettlementPaySelfView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, settlement_id):
        settlement = get_object_or_404(Settlement, id=settlement_id)
        settlement = mark_settlement_paid_self(settlement=settlement, user=request.user)
        return Response(
            SettlementSerializer(settlement, context={"request": request}).data,
            status=status.HTTP_200_OK,
        )


class SettlementProofCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, settlement_id):
        settlement = get_object_or_404(Settlement, id=settlement_id)

        serializer = SettlementProofCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        proof = upload_settlement_proof(
            settlement=settlement,
            user=request.user,
            image_url=serializer.validated_data["image_url"],
        )
        return Response(
            SettlementProofSerializer(proof, context={"request": request}).data,
            status=status.HTTP_201_CREATED,
        )


class SettlementConfirmView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, settlement_id):
        settlement = get_object_or_404(Settlement, id=settlement_id)
        settlement = confirm_settlement(settlement=settlement, user=request.user)
        return Response(
            SettlementSerializer(settlement, context={"request": request}).data,
            status=status.HTTP_200_OK,
        )


class SettlementDisputeView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, settlement_id):
        settlement = get_object_or_404(Settlement, id=settlement_id)
        settlement = dispute_settlement(settlement=settlement, user=request.user)
        return Response(
            SettlementSerializer(settlement, context={"request": request}).data,
            status=status.HTTP_200_OK,
        )