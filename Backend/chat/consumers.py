# chat/consumers.py
import json
from urllib.parse import parse_qs

from asgiref.sync import sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer
from django.contrib.auth.models import AnonymousUser
from rest_framework.authtoken.models import Token

from .models import ChatRoom, ChatMessage


class ChatConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.room_id = self.scope["url_route"]["kwargs"]["trip_id"]
        self.room_group_name = f"chat_{self.room_id}"

        self.user = await self._get_user_from_query_token()

        await self.channel_layer.group_add(
            self.room_group_name,
            self.channel_name,
        )

        await self.accept()

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(
            self.room_group_name,
            self.channel_name,
        )

    @sync_to_async
    def _get_user_from_query_token(self):
        query_string = self.scope.get("query_string", b"").decode("utf-8")
        query_params = parse_qs(query_string)
        token_key = query_params.get("token", [""])[0]

        if not token_key:
            return AnonymousUser()

        try:
            return Token.objects.select_related("user").get(key=token_key).user
        except Token.DoesNotExist:
            return AnonymousUser()

    @sync_to_async
    def _save_chat_message(self, message):
        if not self.user.is_authenticated:
            return None

        room = ChatRoom.objects.get(id=self.room_id)

        chat_message = ChatMessage.objects.create(
            room=room,
            sender_user=self.user,
            message=message,
        )

        return {
            "id": chat_message.id,
            "sender_user_id": self.user.id,
            "sender": self.user.username,
            "message": chat_message.message,
            "sent_at": chat_message.sent_at.isoformat(),
        }
        
    @sync_to_async
    def _save_system_message(self, message):
        if not self.user.is_authenticated:
            return None

        room = ChatRoom.objects.get(id=self.room_id)

        chat_message = ChatMessage.objects.create(
            room=room,
            sender_user=self.user,
            message=message,
            message_type=ChatMessage.MessageTypeChoices.SYSTEM,
        )

        return {
            "id": chat_message.id,
            "sender_user_id": self.user.id,
            "sender": self.user.username,
            "message": chat_message.message,
            "sent_at": chat_message.sent_at.isoformat(),
        }

    @sync_to_async
    def _get_room_notification_user_ids(self):
        try:
            room = ChatRoom.objects.select_related("trip").get(id=self.room_id)
        except ChatRoom.DoesNotExist:
            return []

        user_ids = set()

        if room.trip.leader_user_id:
            user_ids.add(room.trip.leader_user_id)

        joined_user_ids = room.trip.trip_participants.filter(
            status="JOINED",
        ).values_list("user_id", flat=True)

        user_ids.update(joined_user_ids)

        return list(user_ids)

    async def _notify_chat_room_updated(self, saved_message):
        if not saved_message:
            return

        user_ids = await self._get_room_notification_user_ids()

        for user_id in user_ids:
            await self.channel_layer.group_send(
                f"user_{user_id}",
                {
                    "type": "chat_room_updated",
                    "room_id": int(self.room_id),
                    "last_message": saved_message.get("message", ""),
                    "message_type": "TEXT",
                    "sender": saved_message.get("sender", ""),
                    "sender_user_id": saved_message.get("sender_user_id"),
                    "sent_at": saved_message.get("sent_at"),
                },
            )

    async def receive(self, text_data):
        data = json.loads(text_data)

        message_type = data.get("type", "chat_message")

        sender = (
            self.user.username
            if self.user.is_authenticated
            else "익명"
        )

        if message_type == "settlement_request":
            settlement_message = data.get("message", "정산 요청이 도착했습니다.")
            saved_message = await self._save_system_message(settlement_message)

            await self.channel_layer.group_send(
                self.room_group_name,
                {
                    "type": "broadcast_message",
                    "message_type": "settlement_request",
                    "sender": sender,
                    "sender_user_id": self.user.id if self.user.is_authenticated else None,
                    "settlement": data.get("settlement"),
                    "message": settlement_message,
                    "message_id": saved_message["id"] if saved_message else None,
                    "sent_at": saved_message["sent_at"] if saved_message else None,
                },
            )

            user_ids = await self._get_room_notification_user_ids()

            for user_id in user_ids:
                await self.channel_layer.group_send(
                    f"user_{user_id}",
                    {
                        "type": "chat_room_updated",
                        "room_id": int(self.room_id),
                        "last_message": settlement_message,
                        "message_type": "SETTLEMENT_REQUEST",
                        "sender": sender,
                        "sender_user_id": self.user.id if self.user.is_authenticated else None,
                        "sent_at": saved_message["sent_at"] if saved_message else None,
                    },
                )
# 🚀 [추가] 푸시 알림 발송
            await self._send_push_notifications(
                title="💰 정산 요청",
                body=settlement_message,
                fcm_type="SETTLEMENT_REQUEST"
            )
            return

        
        if message_type == "settlement_completed":
            completed_message = data.get("message", "정산이 완료되었습니다.")
            saved_message = await self._save_system_message(completed_message)

            await self.channel_layer.group_send(
                self.room_group_name,
                {
                    "type": "broadcast_message",
                    "message_type": "settlement_completed",
                    "sender": sender,
                    "sender_user_id": self.user.id if self.user.is_authenticated else None,
                    "message": completed_message,
                    "message_id": saved_message["id"] if saved_message else None,
                    "sent_at": saved_message["sent_at"] if saved_message else None,
                    "pinned_notice": data.get("pinned_notice"),
                    "expires_at": data.get("expires_at"),
                },
            )

            user_ids = await self._get_room_notification_user_ids()

            for user_id in user_ids:
                await self.channel_layer.group_send(
                    f"user_{user_id}",
                    {
                        "type": "chat_room_updated",
                        "room_id": int(self.room_id),
                        "last_message": completed_message,
                        "message_type": "SETTLEMENT_COMPLETED",
                        "sender": sender,
                        "sender_user_id": self.user.id if self.user.is_authenticated else None,
                        "sent_at": saved_message["sent_at"] if saved_message else None,
                    },
                )
# 🚀 [추가] 푸시 알림 발송
            await self._send_push_notifications(
                title="✅ 정산 완료",
                body=completed_message,
                fcm_type="SETTLEMENT_COMPLETED"
            )
            return

        message = data.get("message", "")
        saved_message = await self._save_chat_message(message)

        await self.channel_layer.group_send(
            self.room_group_name,
            {
                "type": "broadcast_message",
                "message_type": "chat_message",
                "message": message,
                "sender": sender,
                "sender_user_id": self.user.id if self.user.is_authenticated else None,
                "message_id": saved_message["id"] if saved_message else None,
                "sent_at": saved_message["sent_at"] if saved_message else None,
                
            },
        )
        await self._notify_chat_room_updated(saved_message)
# 🚀 [추가] 푸시 알림 발송 (자신 제외)
        await self._send_push_notifications(
            title=f"💬 {sender}님의 메시지",
            body=message,
            fcm_type="CHAT"
        )
# 🌟 추가: 푸시 알림 발송을 총괄하는 비동기 메서드
    async def _send_push_notifications(self, title, body, fcm_type):
        user_ids = await self._get_room_notification_user_ids()
        # 나(전송자)를 제외한 나머지 인원 필터링
        target_user_ids = [uid for uid in user_ids if uid != self.user.id]

        if target_user_ids:
            await self._dispatch_fcm_to_users(target_user_ids, title, body, fcm_type)

    # 🌟 추가: 실제 DB에서 유저를 조회하고 FCM을 쏘는 동기 메서드
    @sync_to_async
    def _dispatch_fcm_to_users(self, user_ids, title, body, fcm_type):
        from accounts.models import User
        from accounts.utils import send_fcm_notification # 아까 만든 유틸 함수

        # 토큰이 있는 유저들만 조회
        targets = User.objects.filter(id__in=user_ids).exclude(fcm_token__isnull=True).exclude(fcm_token="")

        for target in targets:
            send_fcm_notification(
                user=target,
                title=title,
                body=body,
                data={
                    "room_id": str(self.room_id),
                    "type": fcm_type
                }
            )
    async def broadcast_message(self, event):
        await self.send(
            text_data=json.dumps(
                {
                    "type": event.get("message_type", "chat_message"),
                    "message": event.get("message", ""),
                    "sender": event.get("sender", "익명"),
                    "sender_user_id": event.get("sender_user_id"),
                    "message_id": event.get("message_id"),
                    "sent_at": event.get("sent_at"),
                    "settlement": event.get("settlement"),
                    "image_url": event.get("image_url"),
                    "pinned_notice": event.get("pinned_notice"),
                    "expires_at": event.get("expires_at"),
                },
                ensure_ascii=False,
            )
        )

class NotificationConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.user = await self._get_user_from_query_token()

        if not self.user.is_authenticated:
            await self.close()
            return

        self.user_group_name = f"user_{self.user.id}"

        await self.channel_layer.group_add(
            self.user_group_name,
            self.channel_name,
        )

        await self.accept()

    async def disconnect(self, close_code):
        if hasattr(self, "user_group_name"):
            await self.channel_layer.group_discard(
                self.user_group_name,
                self.channel_name,
            )

    @sync_to_async
    def _get_user_from_query_token(self):
        query_string = self.scope.get("query_string", b"").decode("utf-8")
        query_params = parse_qs(query_string)
        token_key = query_params.get("token", [""])[0]

        if not token_key:
            return AnonymousUser()

        try:
            return Token.objects.select_related("user").get(key=token_key).user
        except Token.DoesNotExist:
            return AnonymousUser()

    async def chat_room_updated(self, event):
        await self.send(
            text_data=json.dumps(
                {
                    "type": "chat_room_updated",
                    "room_id": event.get("room_id"),
                    "last_message": event.get("last_message", ""),
                    "message_type": event.get("message_type", "TEXT"),
                    "sender": event.get("sender", ""),
                    "sender_user_id": event.get("sender_user_id"),
                    "sent_at": event.get("sent_at"),
                },
                ensure_ascii=False,
            )
        )
        
    async def chat_room_removed(self, event):
        await self.send(
            text_data=json.dumps(
                {
                    "type": "chat_room_removed",
                    "room_id": event.get("room_id"),
                    "trip_id": event.get("trip_id"),
                    "reason": event.get("reason", ""),
                },
                ensure_ascii=False,
            )
        )
