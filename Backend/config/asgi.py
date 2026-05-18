# config/asgi.py
import os
from django.core.asgi import get_asgi_application
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.auth import AuthMiddlewareStack
import chat.routing  # 위에서 만든 routing 파일을 불러옵니다.
import trips.routing
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')

# 1. 먼저 장고의 기본 ASGI 어플리케이션을 가져옵니다.
django_asgi_app = get_asgi_application()

application = ProtocolTypeRouter({
    # (HTTP) 일반적인 요청 처리
    "http": django_asgi_app,

    # (WebSocket) 웹소켓 요청 처리
    "websocket": AuthMiddlewareStack(
        URLRouter(
            chat.routing.websocket_urlpatterns+
            trips.routing.websocket_urlpatterns
        )
    ),
})