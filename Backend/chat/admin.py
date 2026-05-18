from django.contrib import admin
from .models import ChatRoom, ChatMessage


@admin.register(ChatRoom)
class ChatRoomAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "trip",
        "short_notice",
        "created_at",
        "expires_at",
        "is_archived",
    )
    list_filter = ("is_archived",)
    search_fields = (
        "trip__id",
        "trip__depart_name",
        "trip__arrive_name",
        "pinned_notice",
    )
    readonly_fields = ("created_at",)

    def short_notice(self, obj):
        if not obj.pinned_notice:
            return "-"
        return obj.pinned_notice[:30]
    short_notice.short_description = "고정 공지"


@admin.register(ChatMessage)
class ChatMessageAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "room",
        "sender_user",
        "short_message",
        "sent_at",
    )
    search_fields = (
        "sender_user__username",
        "sender_user__nickname",
        "message",
    )
    readonly_fields = ("sent_at",)

    def short_message(self, obj):
        return obj.message[:30]
    short_message.short_description = "메시지"