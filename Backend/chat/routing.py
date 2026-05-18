# chat/routing.py
from django.urls import re_path
from . import consumers

websocket_urlpatterns = [
    # ws://서버주소/ws/chat/<trip_id>/ 경로로 들어오는 연결을 ChatConsumer에 연결
    re_path(r'ws/chat/(?P<trip_id>\d+)/$', consumers.ChatConsumer.as_asgi()),

    # 로그인한 사용자별 채팅방 목록/알림 갱신용 WebSocket
    re_path(r'ws/notifications/$', consumers.NotificationConsumer.as_asgi()),
]