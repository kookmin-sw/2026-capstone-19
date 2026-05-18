from django.urls import path
# views.py에서 실제로 만든 4개의 클래스만 가져옵니다.
from .views import (
    SignupView,
    LoginView,
    SendCodeView,
    VerifyCodeView,
    ProfileImageUpdateView,
    TripHistoryView,
    RecentCompanionsView,
    WithdrawView,
    UserProfileView,
    LogoutView,
    UpdatePhoneView,
    UpdateFCMTokenView,
)
from . import views

urlpatterns = [
    # 1. 회원가입 및 본인인증 관련
    path('signup/', SignupView.as_view(), name='signup'),
    path('send-code/', SendCodeView.as_view(), name='send_code'),
    path('verify-code/', VerifyCodeView.as_view(), name='verify_code'),
    path('profile/image/', views.ProfileImageUpdateView.as_view(), name='update-profile-image'),
    path('history/', views.TripHistoryView.as_view(), name='trip-history'),
    path('recent-companions/', views.RecentCompanionsView.as_view(), name='recent-companions'),
    path('withdraw/', views.WithdrawView.as_view(), name='withdraw'),
    path('profile/', views.UserProfileView.as_view(), name='user-profile'),
    path('logout/', LogoutView.as_view(), name='logout'),
    path('profile/image/', views.ProfileImageUpdateView.as_view(), name='update-profile-image'),
    path('update-phone/', UpdatePhoneView.as_view(), name='update_phone'),
    path('fcm-token/', UpdateFCMTokenView.as_view(), name='update_fcm_token'),
    # 2. 로그인
    path('login/', LoginView.as_view(), name='login'),
]