from django.conf import settings
from django.db import models

from trips.models import Trip


class ChatRoom(models.Model):
    trip = models.OneToOneField(
        Trip,
        on_delete=models.CASCADE,
        related_name="chat_room",
    )
    pinned_notice = models.TextField(
        blank=True,
        null=True,
        default="택시 번호 및 만날 위치를 공유해주세요!",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    expires_at = models.DateTimeField(blank=True, null=True)
    is_archived = models.BooleanField(default=False)
    
    def __str__(self):
        return f"ChatRoom for Trip {self.trip_id}"


class ChatMessage(models.Model):
    class MessageTypeChoices(models.TextChoices):
        TEXT = "TEXT", "TEXT"
        IMAGE = "IMAGE", "IMAGE"
        SYSTEM = "SYSTEM", "SYSTEM"

    room = models.ForeignKey(
        ChatRoom,
        on_delete=models.CASCADE,
        related_name="messages",
    )
    sender_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="chat_messages_sent",
    )
    message = models.TextField(blank=True, default="")
    message_type = models.CharField(
        max_length=20,
        choices=MessageTypeChoices.choices,
        default=MessageTypeChoices.TEXT,
    )
    image = models.ImageField(
        upload_to="chat/images/%Y/%m/%d/",
        blank=True,
        null=True,
    )
    sent_at = models.DateTimeField(auto_now_add=True)
    def __str__(self):
        return f"Message {self.id} in Room {self.room_id}"
