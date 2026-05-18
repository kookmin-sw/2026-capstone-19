from django.urls import path
# 1. views.py에 정의된 클래스들을 모두 가져옵니다.
from .views import (
    TripCreateListView,
    TripJoinView,
    MyTripListView,          # 📍 추가됨 (내 내역)
    TripStatusUpdateView,    # 📍 추가됨 (상태 변경 및 삭제)
    TripLeaveView,
)

urlpatterns = [
    # 전체 목록 조회 및 핀 생성 ( GET/POST /api/trips/ )
    path('', TripCreateListView.as_view(), name='trip-list-create'),

    # 📍 내 동승 내역 조회 ( GET /api/trips/my/ )
    # 주의: <int:pk> 보다 위에 있어야 URL 라우팅이 꼬이지 않습니다.
    path('my/', MyTripListView.as_view(), name='my-trip-list'),

    # 특정 핀 참여 ( POST /api/trips/<pk>/join/ )
    path('<int:pk>/join/', TripJoinView.as_view(), name='trip-join'),

    # 참여 취소 (POST /api/trips/<pk>/leave/)
    path('<int:pk>/leave/', TripLeaveView.as_view(), name='trip-leave'),

    # 📍 상태 변경 및 핀 삭제 ( PATCH/DELETE /api/trips/<pk>/ )
    path('<int:pk>/', TripStatusUpdateView.as_view(), name='trip-status-update'),
]