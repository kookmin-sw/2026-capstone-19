from rest_framework import serializers
from .models import Trip, TripParticipant

class TripParticipantSerializer(serializers.ModelSerializer):
    nickname = serializers.ReadOnlyField(source='user.nickname')

    class Meta:
        model = TripParticipant
        fields = ['user', 'nickname', 'role', 'seat_position', 'status']

class TripSerializer(serializers.ModelSerializer):
    current_count = serializers.SerializerMethodField()
    # 참여자 상세 정보도 같이 보고 싶을 때 사용
    participants = TripParticipantSerializer(source='trip_participants', many=True, read_only=True)

    leader_user_id = serializers.IntegerField(source='leader_user.id', read_only=True)
    host_nickname = serializers.SerializerMethodField()
    is_mine = serializers.SerializerMethodField()
    is_joined = serializers.SerializerMethodField()
    kakaopay_link = serializers.ReadOnlyField(source='payment_channel.kakaopay_link')

    # 🟢 2. 현재 이 핀에서 'JOINED' 상태인 참여자들의 좌석 리스트만 뽑기
    taken_seats = serializers.SerializerMethodField()

    class Meta:
        model = Trip
        fields = [
            'id',
            'depart_name', 'depart_lat', 'depart_lng',
            'arrive_name', 'arrive_lat', 'arrive_lng',
            'depart_time', 'capacity', 'status', 'estimated_fare',
            'current_count', 'participants',
            'leader_user_id', 'host_nickname', 'is_mine','is_joined','taken_seats', 'kakaopay_link',
        ]

    def get_current_count(self, obj):
        # JOINED 상태인 멤버만 카운트
        return obj.trip_participants.filter(status="JOINED").count()

    def get_host_nickname(self, obj):
        return obj.leader_user.nickname or obj.leader_user.username

    def get_is_mine(self, obj):
        request = self.context.get('request')
        if not request or not request.user.is_authenticated:
            return False
        return obj.leader_user_id == request.user.id

    def get_taken_seats(self, obj):
            # 현재 트립에서 'JOINED' 상태인 사람들의 'seat_position'만 리스트로 쫙 뽑아줍니다.
            return list(obj.trip_participants.filter(status="JOINED").values_list('seat_position', flat=True))

    # 👇 여기에 이 코드를 추가해 주세요! 👇
    def get_is_joined(self, obj):
        request = self.context.get('request')
        if not request or not request.user.is_authenticated:
            return False

        # 현재 요청을 보낸 유저가 이 여행에 'JOINED' 상태로 참여 중인지 확인
        return obj.trip_participants.filter(user=request.user, status='JOINED').exists()
