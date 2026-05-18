from rest_framework import serializers
from trips.models import Trip
from .models import ChatRoom, ChatMessage


class ChatRoomSerializer(serializers.ModelSerializer):
    trip_id = serializers.IntegerField()
    trip_title = serializers.SerializerMethodField()
    last_message = serializers.SerializerMethodField()
    unread_count = serializers.SerializerMethodField()
    is_leader = serializers.SerializerMethodField()

    class Meta:
        model = ChatRoom
        fields = [
            'id',
            'trip_id',
            'trip_title',
            'last_message',
            'pinned_notice',
            'created_at',
            'unread_count',
            'is_leader',
        ]
        read_only_fields = ['id', 'created_at']

    def validate_trip_id(self, value):
        if not Trip.objects.filter(id=value).exists():
            raise serializers.ValidationError("존재하지 않는 trip_id입니다.")
        return value

    def get_trip_title(self, obj):
        return f"{obj.trip.depart_name} -> {obj.trip.arrive_name}"

    def get_last_message(self, obj):
        last_msg = obj.messages.order_by('-sent_at').first()
        if last_msg:
            return last_msg.message
        return "채팅방이 생성되었습니다."

    def get_unread_count(self, obj):
        return 0
    
    def get_is_leader(self, obj):
        request = self.context.get("request")
        if not request or not request.user or not request.user.is_authenticated:
            return False
        return obj.trip.leader_user_id == request.user.id

    def create(self, validated_data):
        trip_id = validated_data['trip_id']
        pinned_notice = validated_data.get(
            'pinned_notice',
            "택시 번호 및 만날 위치를 꼭 공유해주세요!"
        )

        chat_room, created = ChatRoom.objects.get_or_create(
            trip_id=trip_id,
            defaults={
                'pinned_notice': pinned_notice
            }
        )
        return chat_room


class ChatMessageSerializer(serializers.ModelSerializer):
    sender_user_id = serializers.IntegerField(source="sender_user.id", read_only=True)
    sender_username = serializers.CharField(source="sender_user.username", read_only=True)
    image_url = serializers.SerializerMethodField()

    class Meta:
        model = ChatMessage
        fields = [
            "id",
            "room",
            "sender_user_id",
            "sender_username",
            "message",
            "message_type",
            "image_url",
            "sent_at",
        ]
        read_only_fields = [
            "id",
            "sender_user_id",
            "sender_username",
            "message_type",
            "image_url",
            "sent_at",
        ]

    def get_image_url(self, obj):
        if not obj.image:
            return None

        request = self.context.get("request")
        if request:
            return request.build_absolute_uri(obj.image.url)

        return obj.image.url
