from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status, permissions
from django.db import transaction
from django.utils import timezone
from .models import Trip, TripParticipant
from .serializers import TripSerializer
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from chat.models import ChatRoom, ChatMessage
from settlements.models import Settlement

def notify_chat_room_removed(room_id, trip_id, user_ids, reason):
    if not room_id:
        return

    channel_layer = get_channel_layer()

    if not channel_layer:
        return

    for user_id in user_ids:
        async_to_sync(channel_layer.group_send)(
            f"user_{user_id}",
            {
                "type": "chat_room_removed",
                "room_id": room_id,
                "trip_id": trip_id,
                "reason": reason,
            },
        )


class TripCreateListView(APIView):
    permission_classes = [permissions.IsAuthenticated]



    def get(self, request):
        # 열려있는 핀 목록만 조회
        trips = Trip.objects.filter(status=Trip.StatusChoices.OPEN).order_by('-created_at')
        serializer = TripSerializer(trips, many=True, context={'request': request})
        return Response(serializer.data)

    def post(self, request):
        data = request.data
        flutter_seat = data.get('seat_position')
        kakaopay_link = (data.get("kakaopay_link") or "").strip()

        if not kakaopay_link:
            return Response(
                {'message': '카카오페이 송금 링크는 필수입니다.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # 1. 좌석 매핑 확인
        valid_seats = [choice[0] for choice in TripParticipant.SeatChoices.choices]

        if flutter_seat not in valid_seats:
            return Response({'message': '올바른 좌석을 선택해주세요.'}, status=status.HTTP_400_BAD_REQUEST)

        active_pin_count = TripParticipant.objects.filter(
            user=request.user,
            status=TripParticipant.StatusChoices.JOINED,
        ).exclude(
            trip__status__in=[
                Trip.StatusChoices.COMPLETED,
                Trip.StatusChoices.CANCELED,
            ]
        ).count()
        if active_pin_count >= 2:
            return Response(
                {'message': '동시에 최대 2개의 동승에만 참여할 수 있습니다.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # 2. 트랜잭션 처리 (Trip 생성과 Participant 생성을 한 번에)
        try:
            with transaction.atomic():
                # Trip 생성 (creator와 leader를 현재 유저로 설정)
                serializer = TripSerializer(data=data)
                if serializer.is_valid():
                    trip = serializer.save(
                        creator_user=request.user,
                        leader_user=request.user
                    )

                    # 호스트를 참여자로 등록
                    TripParticipant.objects.create(
                        trip=trip,
                        user=request.user,
                        role=TripParticipant.RoleChoices.LEADER,
                        seat_position=flutter_seat,
                        status=TripParticipant.StatusChoices.JOINED
                    )

                    from settlements.models import PaymentChannel

                    PaymentChannel.objects.update_or_create(
                        trip=trip,
                        defaults={
                            "provider": "KAKAOPAY",
                            "kakaopay_link": kakaopay_link,
                            "updated_by": request.user,
                        },
                    )

                    return Response(serializer.data, status=status.HTTP_201_CREATED)
                return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        except Exception as e:
            return Response({'message': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


class TripJoinView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    SEAT_MAP = {
        "FRONT_PASSENGER": TripParticipant.SeatChoices.FRONT_PASSENGER,
        "REAR_LEFT": TripParticipant.SeatChoices.REAR_LEFT,
        "REAR_RIGHT": TripParticipant.SeatChoices.REAR_RIGHT,
        "REAR_MIDDLE": TripParticipant.SeatChoices.REAR_MIDDLE,
    }

    def post(self, request, pk):
        try:
            trip = Trip.objects.get(pk=pk)
        except Trip.DoesNotExist:
            return Response({"message": "존재하지 않는 핀입니다."}, status=status.HTTP_404_NOT_FOUND)

        # 🌟 1. 현재 참여 인원 계산 (시리얼라이저의 get_current_count 로직과 동일하게)
        current_joined_count = trip.trip_participants.filter(status="JOINED").count()

        # 2. 핀 상태 및 정원 검사
        if trip.status != Trip.StatusChoices.OPEN:
            return Response({"message": "이미 마감되거나 취소된 팀입니다."}, status=status.HTTP_400_BAD_REQUEST)

        if current_joined_count >= trip.capacity:
            return Response({"message": "정원이 모두 찼습니다."}, status=status.HTTP_400_BAD_REQUEST)

        # 3. 이미 참여 중인지 확인 (LEFT/KICKED 이력은 재참여 허용)
        existing_joined = TripParticipant.objects.filter(
            trip=trip,
            user=request.user,
            status=TripParticipant.StatusChoices.JOINED
        ).first()
        if existing_joined:
            return Response({"message": "이미 참여 중인 팀입니다."}, status=status.HTTP_400_BAD_REQUEST)

        active_pin_count = TripParticipant.objects.filter(
            user=request.user,
            status=TripParticipant.StatusChoices.JOINED,
        ).exclude(
            trip__status__in=[
                Trip.StatusChoices.COMPLETED,
                Trip.StatusChoices.CANCELED,
            ]
        ).count()
        if active_pin_count >= 2:
            return Response(
                {"message": "동시에 최대 2개의 동승에만 참여할 수 있습니다."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # 4. 좌석 매핑 및 중복 검사
        flutter_seat = request.data.get('seat_position')
        django_seat = self.SEAT_MAP.get(flutter_seat)

        if not django_seat:
            return Response({'message': '올바른 좌석을 선택해주세요.'}, status=status.HTTP_400_BAD_REQUEST)

        if TripParticipant.objects.filter(trip=trip, seat_position=django_seat, status="JOINED").exists():
            return Response({'message': '이미 선택된 좌석입니다. 다른 좌석을 선택해주세요.'}, status=status.HTTP_400_BAD_REQUEST)

        # 5. 트랜잭션으로 참여자 등록
        try:
            with transaction.atomic():
                existing_participant = TripParticipant.objects.filter(
                    trip=trip,
                    user=request.user,
                ).first()

                if existing_participant:
                    existing_participant.role = TripParticipant.RoleChoices.MEMBER
                    existing_participant.seat_position = django_seat
                    existing_participant.status = TripParticipant.StatusChoices.JOINED
                    existing_participant.left_at = None
                    existing_participant.save(
                        update_fields=["role", "seat_position", "status", "left_at"]
                    )
                else:
                    TripParticipant.objects.create(
                        trip=trip,
                        user=request.user,
                        role=TripParticipant.RoleChoices.MEMBER,
                        seat_position=django_seat,
                        status=TripParticipant.StatusChoices.JOINED,
                    )

                room = ChatRoom.objects.filter(trip=trip).first()

                if room:
                    system_text = f"@{request.user.username} 님이 참여하였습니다."

                    system_message = ChatMessage.objects.create(
                        room=room,
                        sender_user=request.user,
                        message=system_text,
                        message_type=ChatMessage.MessageTypeChoices.SYSTEM,
                    )

                    channel_layer = get_channel_layer()

                    if channel_layer:
                        async_to_sync(channel_layer.group_send)(
                            f"chat_{room.id}",
                            {
                                "type": "broadcast_message",
                                "message_type": "system_message",
                                "message": system_text,
                                "sender": request.user.username,
                                "sender_user_id": request.user.id,
                                "message_id": system_message.id,
                                "sent_at": system_message.sent_at.isoformat(),
                            },
                        )

                        user_ids = set()

                        if trip.leader_user_id:
                            user_ids.add(trip.leader_user_id)

                        joined_user_ids = trip.trip_participants.filter(
                            status=TripParticipant.StatusChoices.JOINED,
                        ).values_list("user_id", flat=True)

                        user_ids.update(joined_user_ids)

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

                # 정원이 다 찼다면 모집 완료(FULL)로 변경
                if (current_joined_count + 1) >= trip.capacity:
                    trip.status = Trip.StatusChoices.FULL
                    trip.save(update_fields=["status"])

            return Response({"success": True, "message": "참여가 완료되었습니다."}, status=status.HTTP_200_OK)

        except Exception as e:
            return Response({'message': f'참여 처리 중 오류가 발생했습니다: {str(e)}'}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


class MyTripListView(APIView):
    """내가 방장이거나, 멤버로 참여 중인 모든 동승 내역 조회"""
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        # 현재 로그인한 유저가 'JOINED' 상태로 포함된 모든 트립
        trips = Trip.objects.filter(
            trip_participants__user=request.user,
            trip_participants__status=TripParticipant.StatusChoices.JOINED
        ).distinct().order_by('-depart_time')

        serializer = TripSerializer(trips, many=True, context={'request': request})
        return Response(serializer.data, status=status.HTTP_200_OK)

class TripStatusUpdateView(APIView):
    """방장이 동승의 상태를 변경하거나 핀을 삭제함"""
    permission_classes = [permissions.IsAuthenticated]

    # 1. 상태 변경 (PATCH) - service.dart의 updateTripStatus와 연결
    def patch(self, request, pk):
        try:
            trip = Trip.objects.get(pk=pk)
        except Trip.DoesNotExist:
            return Response({"message": "존재하지 않는 핀입니다."}, status=status.HTTP_404_NOT_FOUND)

        # 권한 확인: 방장만 상태 변경 가능
        if trip.leader_user != request.user:
            return Response({"message": "상태 변경 권한이 없습니다."}, status=status.HTTP_403_FORBIDDEN)

        new_status = request.data.get('status')

        # 모델의 StatusChoices에 정의된 값인지 확인
        valid_statuses = [choice[0] for choice in Trip.StatusChoices.choices]

        if new_status in valid_statuses:
            trip.status = new_status
            trip.save()
            return Response({"success": True, "status": trip.status}, status=status.HTTP_200_OK)

        return Response({"message": "잘못된 상태 값입니다."}, status=status.HTTP_400_BAD_REQUEST)

    # 2. 📍 핀 삭제 (DELETE) - service.dart의 deleteTrip과 연결되도록 추가됨!
    def delete(self, request, pk):
        try:
            trip = Trip.objects.get(pk=pk)
        except Trip.DoesNotExist:
            return Response({"message": "존재하지 않는 핀입니다."}, status=status.HTTP_404_NOT_FOUND)

        # 권한 확인: 방장만 삭제 가능
        if trip.leader_user != request.user:
            return Response({"message": "삭제 권한이 없습니다."}, status=status.HTTP_403_FORBIDDEN)

        room = ChatRoom.objects.filter(trip=trip).first()
        room_id = room.id if room else None

        user_ids = set()

        if trip.leader_user_id:
            user_ids.add(trip.leader_user_id)

        joined_user_ids = trip.trip_participants.filter(
            status=TripParticipant.StatusChoices.JOINED,
        ).values_list("user_id", flat=True)

        user_ids.update(joined_user_ids)

        trip_id = trip.id

        channel_layer = get_channel_layer()

        if channel_layer and room_id:
            async_to_sync(channel_layer.group_send)(
                f"chat_{room_id}",
                {
                    "type": "broadcast_message",
                    "message_type": "trip_deleted",
                    "message": "리더가 매칭을 삭제했습니다.",
                    "sender": request.user.username,
                    "sender_user_id": request.user.id,
                    "room_id": room_id,
                    "trip_id": trip_id,
                    "reason": "trip_deleted",
                },
            )

        # 핀(방) 삭제
        trip.delete()

        notify_chat_room_removed(
            room_id=room_id,
            trip_id=trip_id,
            user_ids=user_ids,
            reason="trip_deleted",
        )

        # 성공 시 204 No Content 반환
        return Response(status=status.HTTP_204_NO_CONTENT)


class TripLeaveView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        user = request.user
        try:
            trip = Trip.objects.get(pk=pk)
        except Trip.DoesNotExist:
            return Response({"detail": "존재하지 않는 핀입니다."}, status=status.HTTP_404_NOT_FOUND)

        if trip.leader_user_id == user.id:
            return Response(
                {"detail": "방장은 참여 취소할 수 없습니다. 핀 삭제 또는 모집 완료를 이용해주세요."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if Settlement.objects.filter(trip=trip).exists():
            return Response(
                {"detail": "정산이 생성된 이후에는 참여 취소할 수 없습니다."},
                status=status.HTTP_409_CONFLICT,
            )

        try:
            participant = TripParticipant.objects.get(
                trip=trip,
                user=user,
                status=TripParticipant.StatusChoices.JOINED,
            )
        except TripParticipant.DoesNotExist:
            return Response(
                {"detail": "현재 참여 중인 매칭이 아닙니다."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        released_seat = participant.seat_position
        room = ChatRoom.objects.filter(trip=trip).first()
        room_id = room.id if room else None

        with transaction.atomic():
            participant.status = TripParticipant.StatusChoices.LEFT
            participant.seat_position = None
            participant.left_at = timezone.now()
            participant.save(update_fields=["status", "seat_position", "left_at"])

            joined_count = TripParticipant.objects.filter(
                trip=trip,
                status=TripParticipant.StatusChoices.JOINED,
            ).count()

            if joined_count < trip.capacity and trip.status in [Trip.StatusChoices.FULL, Trip.StatusChoices.CLOSED]:
                trip.status = Trip.StatusChoices.OPEN
                trip.save(update_fields=["status"])
  
        if room:
            system_text = f"@{user.username} 님이 퇴장하였습니다."

            system_message = ChatMessage.objects.create(
                room=room,
                sender_user=user,
                message=system_text,
                message_type=ChatMessage.MessageTypeChoices.SYSTEM,
            )

            channel_layer = get_channel_layer()

            if channel_layer:
                async_to_sync(channel_layer.group_send)(
                    f"chat_{room.id}",
                    {
                        "type": "broadcast_message",
                        "message_type": "system_message",
                        "message": system_text,
                        "sender": user.username,
                        "sender_user_id": user.id,
                        "message_id": system_message.id,
                        "sent_at": system_message.sent_at.isoformat(),
                    },
                )

                remaining_user_ids = set()

                if trip.leader_user_id:
                    remaining_user_ids.add(trip.leader_user_id)

                joined_user_ids = trip.trip_participants.filter(
                    status=TripParticipant.StatusChoices.JOINED,
                ).values_list("user_id", flat=True)

                remaining_user_ids.update(joined_user_ids)

                # 나간 사람 본인에게는 N 배지를 만들 필요 없음
                remaining_user_ids.discard(user.id)

                for remaining_user_id in remaining_user_ids:
                    async_to_sync(channel_layer.group_send)(
                        f"user_{remaining_user_id}",
                        {
                            "type": "chat_room_updated",
                            "room_id": room.id,
                            "last_message": system_text,
                            "message_type": "SYSTEM",
                            "sender": user.username,
                            "sender_user_id": user.id,
                            "sent_at": system_message.sent_at.isoformat(),
                        },
                    )
                
        notify_chat_room_removed(
            room_id=room_id,
            trip_id=trip.id,
            user_ids=[user.id],
            reason="trip_left",
        )

        return Response(
            {
                "detail": "매칭 참여가 취소되었습니다.",
                "trip_id": trip.id,
                "participant_status": participant.status,
                "released_seat": released_seat,
            },
            status=status.HTTP_200_OK,
        )