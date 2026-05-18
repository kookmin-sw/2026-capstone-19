from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from django.db.models import Q
from django.utils import timezone
from .models import ChatRoom, ChatMessage
from .serializers import ChatRoomSerializer, ChatMessageSerializer
from trips.models import Trip, TripParticipant
from rest_framework.parsers import MultiPartParser, FormParser
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
import logging
from django.db import transaction
from settlements.models import Settlement

logger = logging.getLogger(__name__)



class ChatRoomListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    # 🌟 [변경됨] DB 수정 없이 Trip과의 관계를 이용해 목록 가져오기
    def get(self, request):
        user = request.user

        # 내가 리더인 트립
        leader_trip_ids = Trip.objects.filter(
            leader_user=user
        ).values_list("id", flat=True)

        # 내가 참여 중인 트립
        participant_trip_ids = TripParticipant.objects.filter(
            user=user,
            status="JOINED",
        ).values_list("trip_id", flat=True)

        # 만료된 채팅방은 목록 조회 시 아카이브 처리
        now = timezone.now()

        ChatRoom.objects.filter(
            is_archived=False,
            expires_at__isnull=False,
            expires_at__lte=now,
        ).update(is_archived=True)

        rooms = ChatRoom.objects.filter(
            Q(trip_id__in=leader_trip_ids) |
            Q(trip_id__in=participant_trip_ids),
            is_archived=False,
        ).distinct().order_by("-created_at")

        serializer = ChatRoomSerializer(
            rooms,
            many=True,
            context={"request": request},
        )
        return Response(serializer.data, status=status.HTTP_200_OK)

    # 채팅방 개설 (참여자 추가 로직 삭제됨)
    def post(self, request):
        serializer = ChatRoomSerializer(data=request.data)
        if serializer.is_valid():
            chat_room = serializer.save()
            # DB 수정(participants 필드)을 안 하므로, 여기서는 그냥 방만 만듭니다.
            return Response({"id": chat_room.id}, status=status.HTTP_201_CREATED)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
    
class ChatRoomCreateView(APIView):
    def post(self, request):
        return Response(
            {"message": "Chat room create endpoint is temporarily available."},
            status=status.HTTP_201_CREATED,
        )
        
class ChatRoomParticipantsView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, room_id):
        user = request.user

        try:
            room = ChatRoom.objects.select_related(
                "trip",
                "trip__leader_user",
            ).get(id=room_id)
        except ChatRoom.DoesNotExist:
            return Response(
                {"detail": "채팅방을 찾을 수 없습니다."},
                status=status.HTTP_404_NOT_FOUND,
            )

        trip = room.trip

        is_leader = trip.leader_user_id == user.id
        is_participant = TripParticipant.objects.filter(
            trip=trip,
            user=user,
            status=TripParticipant.StatusChoices.JOINED,
        ).exists()

        if not is_leader and not is_participant:
            return Response(
                {"detail": "이 채팅방의 참여자 목록을 조회할 권한이 없습니다."},
                status=status.HTTP_403_FORBIDDEN,
            )

        leader_participant = TripParticipant.objects.filter(
            trip=trip,
            user=trip.leader_user,
            status=TripParticipant.StatusChoices.JOINED,
        ).first()

        participants = [
            {
                "user_id": trip.leader_user.id,
                "username": trip.leader_user.username,
                "role": "LEADER",
                "status": "JOINED",
                "seat_position": leader_participant.seat_position if leader_participant else None,
            }
        ]

        joined_members = (
            TripParticipant.objects
            .filter(
                trip=trip,
                status=TripParticipant.StatusChoices.JOINED,
            )
            .select_related("user")
            .exclude(user_id=trip.leader_user_id)
            .order_by("joined_at")
        )

        for participant in joined_members:
            participants.append(
                {
                    "user_id": participant.user.id,
                    "username": participant.user.username,
                    "role": participant.role,
                    "status": participant.status,
                    "seat_position": participant.seat_position,
                }
            )

        return Response(
            {
                "room_id": room.id,
                "trip_id": trip.id,
                "participants": participants,
            },
            status=status.HTTP_200_OK,
        )

class ChatRoomLeaveView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, room_id):
        user = request.user

        try:
            room = ChatRoom.objects.select_related("trip").get(id=room_id)
        except ChatRoom.DoesNotExist:
            return Response(
                {"detail": "채팅방을 찾을 수 없습니다."},
                status=status.HTTP_404_NOT_FOUND,
            )

        trip = room.trip

        if trip.leader_user_id == user.id:
            return Response(
                {"detail": "리더는 채팅방을 나갈 수 없습니다. 모집 완료 또는 핀 삭제 기능을 이용해주세요."},
                status=status.HTTP_400_BAD_REQUEST,
            )
            
        if trip.status in [
            Trip.StatusChoices.FULL,
            Trip.StatusChoices.CLOSED,
            Trip.StatusChoices.COMPLETED,
        ]:
            return Response(
                {"detail": "모집이 완료된 이후에는 채팅방을 나갈 수 없습니다."},
                status=status.HTTP_409_CONFLICT,
            )

        if Settlement.objects.filter(trip=trip).exists():
            return Response(
                {"detail": "정산이 생성된 이후에는 채팅방을 나갈 수 없습니다."},
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

        with transaction.atomic():
            participant.status = TripParticipant.StatusChoices.LEFT
            participant.seat_position = None
            participant.left_at = timezone.now()
            participant.save(update_fields=["status", "seat_position", "left_at"])

            joined_count = TripParticipant.objects.filter(
                trip=trip,
                status=TripParticipant.StatusChoices.JOINED,
            ).count()

            if trip.status == Trip.StatusChoices.FULL and joined_count < trip.capacity:
                trip.status = Trip.StatusChoices.OPEN
                trip.save(update_fields=["status"])

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
                            "sender": user.username,
                            "sender_user_id": user.id,
                            "sent_at": system_message.sent_at.isoformat(),
                        },
                    )

        return Response(
            {
                "detail": "채팅방과 매칭에서 나갔습니다.",
                "trip_id": trip.id,
                "participant_status": participant.status,
                "released_seat": released_seat,
            },
            status=status.HTTP_200_OK,
        )

class ChatRoomMessageListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, room_id):
        user = request.user

        try:
            room = ChatRoom.objects.select_related("trip").get(id=room_id)
        except ChatRoom.DoesNotExist:
            return Response(
                {"detail": "채팅방을 찾을 수 없습니다."},
                status=status.HTTP_404_NOT_FOUND,
            )

        is_leader = room.trip.leader_user_id == user.id
        is_participant = TripParticipant.objects.filter(
            trip=room.trip,
            user=user,
            status="JOINED",
        ).exists()

        if not is_leader and not is_participant:
            return Response(
                {"detail": "이 채팅방의 메시지를 조회할 권한이 없습니다."},
                status=status.HTTP_403_FORBIDDEN,
            )

        messages = ChatMessage.objects.filter(
            room=room,
        ).select_related("sender_user").order_by("sent_at")

        serializer = ChatMessageSerializer(
            messages,
            many=True,
            context={"request": request},
        )
        return Response(serializer.data, status=status.HTTP_200_OK)
    
    
class ChatImageMessageCreateView(APIView):
    permission_classes = [IsAuthenticated]
    parser_classes = (MultiPartParser, FormParser)

    def post(self, request, room_id):
        user = request.user

        try:
            room = ChatRoom.objects.select_related("trip").get(id=room_id)
        except ChatRoom.DoesNotExist:
            return Response(
                {"detail": "채팅방을 찾을 수 없습니다."},
                status=status.HTTP_404_NOT_FOUND,
            )

        is_leader = room.trip.leader_user_id == user.id
        is_participant = TripParticipant.objects.filter(
            trip=room.trip,
            user=user,
            status="JOINED",
        ).exists()

        if not is_leader and not is_participant:
            return Response(
                {"detail": "이 채팅방에 이미지를 보낼 권한이 없습니다."},
                status=status.HTTP_403_FORBIDDEN,
            )

        image = request.FILES.get("image")
        if not image:
            return Response(
                {"detail": "image 파일이 필요합니다."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        chat_message = ChatMessage.objects.create(
            room=room,
            sender_user=user,
            message="",
            message_type="IMAGE",
            image=image,
        )

        serializer = ChatMessageSerializer(
            chat_message,
            context={"request": request},
        )
        data = serializer.data

        channel_layer = get_channel_layer()
        if channel_layer:
            event = {
                "type": "broadcast_message",
                "message_type": "image_message",
                "message": "",
                "sender": user.username,
                "sender_user_id": user.id,
                "message_id": data.get("id"),
                "sent_at": str(data.get("sent_at")) if data.get("sent_at") else None,
                "image_url": data.get("image_url"),
            }

            try:
                async_to_sync(channel_layer.group_send)(
                    f"chat_{room.id}",
                    event,
                )
            except Exception:
                logger.exception(
                    "Chat image broadcast failed. room_id=%s, trip_id=%s, message_id=%s",
                    room.id,
                    room.trip_id,
                    data.get("id"),
                )
            try:
                user_ids = set()

                if room.trip.leader_user_id:
                    user_ids.add(room.trip.leader_user_id)

                joined_user_ids = room.trip.trip_participants.filter(
                    status=TripParticipant.StatusChoices.JOINED,
                ).values_list("user_id", flat=True)

                user_ids.update(joined_user_ids)

                for user_id in user_ids:
                    async_to_sync(channel_layer.group_send)(
                        f"user_{user_id}",
                        {
                            "type": "chat_room_updated",
                            "room_id": room.id,
                            "last_message": "사진을 보냈습니다.",
                            "message_type": "IMAGE",
                            "sender": user.username,
                            "sender_user_id": user.id,
                            "sent_at": str(data.get("sent_at")) if data.get("sent_at") else None,
                        },
                    )
            except Exception:
                logger.exception(
                    "Chat image notification failed. room_id=%s, trip_id=%s, message_id=%s",
                    room.id,
                    room.trip_id,
                    data.get("id"),
                )

        return Response(data, status=status.HTTP_201_CREATED)
