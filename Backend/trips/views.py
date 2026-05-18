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
from accounts.models import User  # 유저 모델
from accounts.utils import send_fcm_notification

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

            # ✅ 올바른 위치: DB에서 불러온 직후, try 블록 안에서 검사
            if trip.leader_user == request.user:
                return Response({"message": "방장은 이미 참여 중입니다."}, status=status.HTTP_400_BAD_REQUEST)

        except Trip.DoesNotExist:
            return Response({"message": "존재하지 않는 핀입니다."}, status=status.HTTP_404_NOT_FOUND)

        # 1. 현재 참여 인원 계산
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

        # 4. 좌석 매핑 및 중복 검사
        flutter_seat = request.data.get('seat_position')
        django_seat = self.SEAT_MAP.get(flutter_seat)

        if not django_seat:
            return Response({'message': '올바른 좌석을 선택해주세요.'}, status=status.HTTP_400_BAD_REQUEST)

        if TripParticipant.objects.filter(trip=trip, seat_position=django_seat, status="JOINED").exists():
            return Response({'message': '이미 선택된 좌석입니다. 다른 좌석을 선택해주세요.'}, status=status.HTTP_400_BAD_REQUEST)

        # 5. 트랜잭션으로 참여자 등록
        try:
            # ✅ 들여쓰기 라인 통일
            room_info = None
            target_user_ids = []
            system_text = ""

            with transaction.atomic():
                # 1. 참여자 등록/업데이트
                existing_participant = TripParticipant.objects.filter(trip=trip, user=request.user).first()
                if existing_participant:
                    existing_participant.role = TripParticipant.RoleChoices.MEMBER
                    existing_participant.seat_position = django_seat
                    existing_participant.status = TripParticipant.StatusChoices.JOINED
                    existing_participant.left_at = None
                    existing_participant.save(update_fields=["role", "seat_position", "status", "left_at"])
                else:
                    TripParticipant.objects.create(
                        trip=trip, user=request.user, role=TripParticipant.RoleChoices.MEMBER,
                        seat_position=django_seat, status=TripParticipant.StatusChoices.JOINED
                    )

                # 2. 시스템 메시지 저장
                room = ChatRoom.objects.filter(trip=trip).first()
                if room:
                    system_text = f"@{request.user.username} 님이 참여하였습니다."
                    system_message = ChatMessage.objects.create(
                        room=room, sender_user=request.user, message=system_text,
                        message_type=ChatMessage.MessageTypeChoices.SYSTEM,
                    )

                    room_info = {
                        "id": room.id,
                        "message_id": system_message.id,
                        "sent_at": system_message.sent_at.isoformat()
                    }

                    user_ids = set()
                    if trip.leader_user_id:
                        user_ids.add(trip.leader_user_id)
                    joined_user_ids = trip.trip_participants.filter(status="JOINED").values_list("user_id", flat=True)
                    user_ids.update(joined_user_ids)

                    target_user_ids = [uid for uid in user_ids if uid != request.user.id]

                # 3. 정원 확인 및 핀 상태 변경
                if (current_joined_count + 1) >= trip.capacity:
                    trip.status = Trip.StatusChoices.FULL
                    trip.save(update_fields=["status"])

            # ---------------------------------------------------------
            # 🚀 트랜잭션 밖 비동기 알림 처리
            # ---------------------------------------------------------
            if room_info:
                channel_layer = get_channel_layer()
                if channel_layer:
                    async_to_sync(channel_layer.group_send)(
                        f"chat_{room_info['id']}",
                        {
                            "type": "broadcast_message",
                            "message_type": "system_message",
                            "message": system_text,
                            "sender": request.user.username,
                            "sender_user_id": request.user.id,
                            "message_id": room_info['message_id'],
                            "sent_at": room_info['sent_at'],
                        },
                    )

                    all_active_ids = target_user_ids + [request.user.id]
                    for user_id in all_active_ids:
                        async_to_sync(channel_layer.group_send)(
                            f"user_{user_id}",
                            {
                                "type": "chat_room_updated",
                                "room_id": room_info['id'],
                                "last_message": system_text,
                                "message_type": "SYSTEM",
                                "sender": request.user.username,
                                "sender_user_id": request.user.id,
                                "sent_at": room_info['sent_at'],
                            },
                        )

                if target_user_ids:
                    from accounts.models import User
                    from accounts.utils import send_fcm_notification

                    targets = User.objects.filter(id__in=target_user_ids).exclude(fcm_token__isnull=True).exclude(fcm_token="")
                    for target in targets:
                        send_fcm_notification(
                            user=target,
                            title="새로운 동승자 참여",
                            body=system_text,
                            data={"room_id": str(room_info['id']), "type": "TRIP_JOIN"}
                        )

            return Response({"success": True, "message": "참여가 완료되었습니다."}, status=status.HTTP_200_OK)

        except Exception as e:
            return Response({'message': f'참여 처리 중 오류가 발생했습니다: {str(e)}'}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

class MyTripListView(APIView):
    """내가 방장이거나 멤버로 참여 중인 모든 동승 내역 조회"""
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        # 현재 로그인한 유저가 JOINED 상태이고,
        # 연결된 채팅방이 실제로 존재하며 아카이브되지 않은 트립만 이용중으로 반환
        trips = Trip.objects.filter(
            trip_participants__user=request.user,
            trip_participants__status=TripParticipant.StatusChoices.JOINED,
            chat_room__isnull=False,
            chat_room__is_archived=False,
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
# 🚀 [추가] 실시간 웹소켓 신호 발송
            channel_layer = get_channel_layer()
            if channel_layer:
                async_to_sync(channel_layer.group_send)(
                    f"trip_{trip.id}",  # 프론트엔드 ActiveTab에서 구독 중인 채널
                    {
                        "type": "trip_update", # 소켓 컨슈머의 메서드명과 매칭
                        "status": trip.status,
                        "message": "status_updated"
                    }
                )
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

        # 정산이 생성된 매칭은 삭제 방지
        if Settlement.objects.filter(trip=trip).exists():
            return Response(
                {"message": "정산이 생성된 매칭은 삭제할 수 없습니다."},
                status=status.HTTP_409_CONFLICT,
            )

        room = ChatRoom.objects.filter(trip=trip).first()
        room_id = room.id if room else None
        trip_id = trip.id

        user_ids = set()

        if trip.leader_user_id:
            user_ids.add(trip.leader_user_id)

        joined_user_ids = trip.trip_participants.filter(
            status=TripParticipant.StatusChoices.JOINED,
        ).values_list("user_id", flat=True)

        user_ids.update(joined_user_ids)

        channel_layer = get_channel_layer()

        # 채팅방 안에 있는 사용자에게 매칭 삭제 이벤트 전송
        if channel_layer and room_id:
            trip_deleted_event = {
                "type": "broadcast_message",
                "message_type": "trip_deleted",
                "message": "리더가 매칭을 삭제했습니다.",
                "sender": request.user.username,
                "sender_user_id": request.user.id,
                "room_id": room_id,
                "trip_id": trip_id,
                "reason": "trip_deleted",
            }

            async_to_sync(channel_layer.group_send)(
                f"chat_{room_id}",
                trip_deleted_event,
            )

            if room_id != trip_id:
                async_to_sync(channel_layer.group_send)(
                    f"chat_{trip_id}",
                    trip_deleted_event,
                )

        # ActiveTab 등 trip 상태 구독 화면에 삭제 이벤트 전송
        if channel_layer:
            async_to_sync(channel_layer.group_send)(
                f"trip_{trip_id}",
                {
                    "type": "trip_update",
                    "status": "DELETED",
                    "message": "trip_deleted",
                },
            )

        # 핀/매칭은 실제 삭제하지 않고 취소 상태로 전환한다.
        # 실제 삭제하면 Trip -> ChatRoom -> ChatMessage CASCADE로 채팅 증빙이 사라질 수 있다.
        trip.status = Trip.StatusChoices.CANCELED
        trip.save(update_fields=["status"])

        if room:
            now = timezone.now()

            ChatMessage.objects.create(
                room=room,
                sender_user=request.user,
                message="리더가 매칭을 삭제했습니다.",
                message_type=ChatMessage.MessageTypeChoices.SYSTEM,
            )

            room.pinned_notice = "리더가 매칭을 삭제했습니다."
            room.expires_at = now
            room.is_archived = True
            room.save(update_fields=["pinned_notice", "expires_at", "is_archived"])

        # 채팅방 목록에 있는 사용자에게 방 제거 이벤트 전송
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

        # 방장 체크 및 정산 여부 체크 (기존과 동일)
        if trip.leader_user_id == user.id:
            return Response({"detail": "방장은 참여 취소할 수 없습니다."}, status=status.HTTP_400_BAD_REQUEST)
        if Settlement.objects.filter(trip=trip).exists():
            return Response({"detail": "정산 생성 이후 취소 불가"}, status=status.HTTP_409_CONFLICT)

        try:
            participant = TripParticipant.objects.get(trip=trip, user=user, status="JOINED")
        except TripParticipant.DoesNotExist:
            return Response({"detail": "참여 중인 매칭이 아닙니다."}, status=status.HTTP_400_BAD_REQUEST)

        released_seat = participant.seat_position
        room = ChatRoom.objects.filter(trip=trip).first()
        room_id = room.id if room else None

        with transaction.atomic():
            participant.status = TripParticipant.StatusChoices.LEFT
            participant.seat_position = None
            participant.left_at = timezone.now()
            participant.save(update_fields=["status", "seat_position", "left_at"])

            joined_count = TripParticipant.objects.filter(trip=trip, status="JOINED").count()

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
                leave_event = {
                    "type": "broadcast_message",
                    "message_type": "system_message",
                    "message": system_text,
                    "sender": user.username,
                    "sender_user_id": user.id,
                    "message_id": system_message.id,
                    "sent_at": system_message.sent_at.isoformat(),
                }

                async_to_sync(channel_layer.group_send)(
                    f"chat_{room.id}",
                    leave_event,
                )

                if room.id != trip.id:
                    async_to_sync(channel_layer.group_send)(
                        f"chat_{trip.id}",
                        leave_event,
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

        # 🚀 알림 발송 (트랜잭션 밖에서 처리)
        room = ChatRoom.objects.filter(trip=trip).first()
        if room:
            leave_text = f"@{user.username} 님이 참여를 취소했습니다."
            active_user_ids = list(trip.trip_participants.filter(status="JOINED").values_list("user_id", flat=True))
            if trip.leader_user_id:
                active_user_ids.append(trip.leader_user_id)

            targets = User.objects.filter(id__in=set(active_user_ids)).exclude(fcm_token__isnull=True).exclude(fcm_token="")
            for target in targets:
                send_fcm_notification(
                    user=target,
                    title="참여 취소 알림",
                    body=leave_text,
                    data={"room_id": str(room.id), "type": "TRIP_LEAVE"}
                )

        return Response({
            "detail": "매칭 참여가 취소되었습니다.",
            "trip_id": trip.id,
            "participant_status": participant.status,
            "released_seat": released_seat,
        }, status=status.HTTP_200_OK)
