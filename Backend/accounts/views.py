import os
import random
import requests
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.authtoken.models import Token
from django.contrib.auth import authenticate
from django.views.decorators.csrf import csrf_exempt
from django.utils.decorators import method_decorator
from .models import User, WithdrawalBlock
from .serializers import SignUpSerializer
from trips.models import TripParticipant
from django.utils import timezone
from datetime import timedelta

# 옥토모 역발상 인증 설정 (.env 파일에서 로드)
OCTOMO_API_KEY = os.getenv('OCTOMO_API_KEY', '')
OCTOMO_API_URL = 'https://api.octoverse.kr/octomo/v1/public/message/exists'
OCTOMO_PHONE_NUMBER = '1666-3538'


# 인증 코드 저장소 (메모리 기반, TTL 5분)
class CodeStore:
    def __init__(self):
        self._store = {}
        self._ttl_seconds = 300  # 5분

    def set(self, phone_number: str, code: str):
        """코드 저장 with TTL"""
        self._store[phone_number] = {
            'code': code,
            'created_at': timezone.now()
        }

    def get(self, phone_number: str) -> str | None:
        """코드 조회 (만료 시 None 반환)"""
        entry = self._store.get(phone_number)
        if not entry:
            return None

        # TTL 체크
        if timezone.now() - entry['created_at'] > timedelta(seconds=self._ttl_seconds):
            del self._store[phone_number]
            return None

        return entry['code']

    def delete(self, phone_number: str):
        """코드 삭제"""
        if phone_number in self._store:
            del self._store[phone_number]


# 전역 코드 저장소 인스턴스
_verification_code_store = CodeStore()


def _generate_six_digit_code() -> str:
    """6자리 랜덤 숫자 코드 생성"""
    return str(random.randint(100000, 999999))


class SignupView(APIView):
    authentication_classes = ()
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = SignUpSerializer(data=request.data)
        if serializer.is_valid():
            serializer.save()
            return Response(
                {'success': True, 'message': '회원가입 성공!'},
                status=status.HTTP_201_CREATED
            )
        return Response(
            {'success': False, 'message': serializer.errors},
            status=status.HTTP_400_BAD_REQUEST
        )


class LoginView(APIView):
    authentication_classes = ()
    permission_classes = [AllowAny]

    def post(self, request):
        username = request.data.get('username')
        password = request.data.get('password')

        user = authenticate(username=username, password=password)

        if user is not None:
            token, created = Token.objects.get_or_create(user=user)
            return Response({
                'success': True,
                'token': token.key,
                'username': user.username,
            }, status=status.HTTP_200_OK)
        else:
            return Response({
                'success': False,
                'message': '아이디 또는 비밀번호가 틀렸습니다.'
            }, status=status.HTTP_401_UNAUTHORIZED)


@method_decorator(csrf_exempt, name='dispatch')
class SendCodeView(APIView):
    authentication_classes = ()
    permission_classes = [AllowAny]

    def post(self, request):
        phone_number = request.data.get('phone', '').strip()
        if not phone_number or len(phone_number) < 10:
            return Response(
                {'success': False, 'message': '올바른 전화번호를 입력해주세요.'},
                status=status.HTTP_400_BAD_REQUEST
            )
        code = _generate_six_digit_code()
        _verification_code_store.set(phone_number, code)
        return Response({
            'success': True,
            'code': code,
            'octomoNumber': OCTOMO_PHONE_NUMBER,
            'message': f'{OCTOMO_PHONE_NUMBER}로 코드 {code}를 SMS 발송해주세요.'
        })


@method_decorator(csrf_exempt, name='dispatch')
class VerifyCodeView(APIView):
    authentication_classes = ()
    permission_classes = [AllowAny]

    def post(self, request):
        phone_number = request.data.get('phone', '').strip()
        if not phone_number:
            return Response(
                {'success': False, 'verified': False, 'message': '전화번호가 필요합니다.'},
                status=status.HTTP_400_BAD_REQUEST
            )
        code = _verification_code_store.get(phone_number)
        if not code:
            return Response(
                {'success': False, 'verified': False, 'message': '인증 코드가 만료되었거나 존재하지 않습니다.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        try:
            if not OCTOMO_API_KEY:
                return Response(
                    {'success': False, 'verified': False, 'message': '인증 서버 설정 오류가 발생했습니다.'},
                    status=status.HTTP_500_INTERNAL_SERVER_ERROR
                )

            headers = {'Content-Type': 'application/json', 'Authorization': f'Octomo {OCTOMO_API_KEY}'}
            body = {'mobileNum': phone_number, 'text': code}
            response = requests.post(OCTOMO_API_URL, headers=headers, json=body, timeout=5)

            if not response.ok:
                return Response(
                    {'success': False, 'verified': False, 'message': '인증 서버 오류가 발생했습니다.'},
                    status=status.HTTP_502_BAD_GATEWAY
                )

            data = response.json()
            verified = data.get('verified', False) or data.get('exists', False)

            if verified:
                _verification_code_store.delete(phone_number)
                return Response({'success': True, 'verified': True, 'message': '전화번호 인증이 완료되었습니다.'})
            else:
                return Response({'success': False, 'verified': False, 'message': '인증 메시지가 확인되지 않았습니다.'})
        except requests.exceptions.RequestException:
            return Response({'success': False, 'verified': False, 'message': '인증 서버 연결 오류'},
                            status=status.HTTP_502_BAD_GATEWAY)


class ProfileImageUpdateView(APIView):
    permission_classes = [IsAuthenticated]
    parser_classes = (MultiPartParser, FormParser)

    def post(self, request):
        user = request.user
        if 'profile_image' in request.FILES:
            user.profile_img_url = request.FILES['profile_image']
            user.save()
            return Response({"message": "Profile image updated successfully"}, status=status.HTTP_200_OK)
        return Response({"error": "No image provided"}, status=status.HTTP_400_BAD_REQUEST)


class TripHistoryView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        participants = TripParticipant.objects.filter(user=request.user).select_related('trip').order_by(
            '-trip__depart_time')
        history_data = []

        for p in participants:
            trip = p.trip
            members_count = TripParticipant.objects.filter(trip=trip, status='JOINED').count()
            total_fare = trip.estimated_fare or 0
            # 💡 들여쓰기 수정 완료!
            my_fare = int(total_fare / members_count) if members_count > 0 else 0

            history_data.append({
                "date": trip.depart_time.strftime("%Y.%m.%d") if trip.depart_time else "날짜 미정",
                "status": trip.status,
                "team": f"{trip.depart_name} -> {trip.arrive_name}",
                "dept": trip.depart_name,
                "dest": trip.arrive_name,
                "members": members_count,
                "total": total_fare,
                "my": my_fare,
            })
        # 💡 return 위치를 for 루프 밖으로 수정 완료!
        return Response(history_data, status=status.HTTP_200_OK)


class RecentCompanionsView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        my_trip_ids = TripParticipant.objects.filter(user=request.user).values_list('trip_id', flat=True)
        companions = TripParticipant.objects.filter(trip_id__in=my_trip_ids).exclude(user=request.user).select_related(
            'user', 'trip').order_by('-trip__depart_time')

        companion_data = []
        seen_user_ids = set()
        for c in companions:
            if c.user.id not in seen_user_ids:
                seen_user_ids.add(c.user.id)
                companion_data.append({
                    "id": str(c.user.id),
                    "nickname": c.user.nickname,
                    "ride_date": c.trip.depart_time.strftime("%Y.%m.%d"),
                    "route": f"{c.trip.depart_name} -> {c.trip.arrive_name}",
                    "profile_image": str(c.user.profile_img_url) if c.user.profile_img_url else ""
                })
        return Response(companion_data, status=status.HTTP_200_OK)


class WithdrawView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        user = request.user
        reason = request.data.get('reason', '자진 탈퇴')
        is_blocked = False

        if user.trust_score < 3.0 or user.penalty_points > 0:
            is_blocked = True
            blocked_until = timezone.now() + timedelta(days=365)
            WithdrawalBlock.objects.create(
                withdrawn_user=user, phone_number=user.phone_number,
                blocked_until=blocked_until, trust_score_at_withdrawal=user.trust_score,
                reason=reason, status='BLOCKED'
            )

        user.is_active = False
        user.fcm_token = None
        user.save()
        return Response({
            "is_blocked": is_blocked,
            "message": "탈퇴 처리가 완료되었습니다." if not is_blocked else "탈퇴 완료 (1년 재가입 제한)"
        }, status=status.HTTP_200_OK)


class UserProfileView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        user = request.user
        return Response({
            'success': True,
            'data': {
                'user_real_name': user.user_real_name,
                'username': user.username,
                'nickname': user.nickname,
                'trust_score': float(user.trust_score),
                'successful_streak_count': user.successful_streak_count,
                'profile_img_url': user.profile_img_url.url if user.profile_img_url else None,
            }
        }, status=status.HTTP_200_OK)


class LogoutView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        try:
            user = request.user
            # 1. FCM 토큰 삭제 (로그아웃한 기기로 알림 방지)
            user.fcm_token = None
            user.save()

            # 2. 인증 토큰 삭제
            user.auth_token.delete()

            return Response({"success": True, "message": "성공적으로 로그아웃 되었습니다."}, status=status.HTTP_200_OK)
        except Exception:
            return Response({"success": False, "message": "로그아웃 처리 중 오류 발생"}, status=status.HTTP_400_BAD_REQUEST)

class UpdatePhoneView(APIView):
    """
    로그인한 사용자의 전화번호를 옥토모 인증 후 실제로 DB에 갱신하는 뷰
    """
    permission_classes = [IsAuthenticated] # 📍 로그인 필수

    def post(self, request):
        user = request.user
        phone_number = request.data.get('phone', '').strip()

        if not phone_number:
            return Response(
                {'success': False, 'message': '전화번호가 필요합니다.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # 1. 메모리 저장소에서 해당 번호의 인증 코드 추출
        code = _verification_code_store.get(phone_number)
        if not code:
            return Response(
                {'success': False, 'message': '인증 코드가 만료되었거나 존재하지 않습니다.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        try:
            if not OCTOMO_API_KEY:
                return Response(
                    {'success': False, 'message': '인증 서버 설정 오류가 발생했습니다.'},
                    status=status.HTTP_500_INTERNAL_SERVER_ERROR
                )

            # 2. 옥토모 API 호출 (실제 SMS 발송 여부 확인)
            headers = {'Content-Type': 'application/json', 'Authorization': f'Octomo {OCTOMO_API_KEY}'}
            body = {'mobileNum': phone_number, 'text': code}
            response = requests.post(OCTOMO_API_URL, headers=headers, json=body, timeout=5)

            if not response.ok:
                return Response(
                    {'success': False, 'message': '인증 서버 오류가 발생했습니다.'},
                    status=status.HTTP_502_BAD_GATEWAY
                )

            data = response.json()
            verified = data.get('verified', False) or data.get('exists', False)

            if verified:
                # 📍 3. 실제 DB 데이터 갱신 (핵심 로직)
                # 이미 다른 사람이 이 번호를 사용 중인지 체크
                if User.objects.exclude(id=user.id).filter(phone_number=phone_number).exists():
                    return Response(
                        {'success': False, 'message': '이미 다른 계정에서 사용 중인 번호입니다.'},
                        status=status.HTTP_400_BAD_REQUEST
                    )

                user.phone_number = phone_number
                # 만약 모델에 is_phone_verified 필드가 있다면 아래 주석 해제
                # user.is_phone_verified = True
                user.save()

                # 인증 완료 후 코드 삭제
                _verification_code_store.delete(phone_number)

                return Response({
                    'success': True,
                    'message': '전화번호 인증 및 변경이 완료되었습니다.',
                    'phone': user.phone_number
                })
            else:
                return Response({'success': False, 'message': '인증 메시지가 확인되지 않았습니다.'})

        except requests.exceptions.RequestException:
            return Response({'success': False, 'message': '인증 서버 연결 오류'},
                            status=status.HTTP_502_BAD_GATEWAY)
class UserProfileView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        user = request.user
        return Response({
            'success': True,
            'data': {
                'user_real_name': user.user_real_name,
                'username': user.username,
                'nickname': user.nickname,
                'trust_score': float(user.trust_score),
                'successful_streak_count': user.successful_streak_count,
                'profile_img_url': user.profile_img_url.url if user.profile_img_url else None,
                # 📍 추가: DB에 추가한 인증 필드값을 내려줍니다.
                'is_phone_verified': getattr(user, 'is_phone_verified', False),
            }
        }, status=status.HTTP_200_OK)
class UpdateFCMTokenView(APIView):
    """
    사용자의 FCM 기기 토큰을 업데이트하는 뷰
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        fcm_token = request.data.get('fcm_token')
        if not fcm_token:
            return Response(
                {'success': False, 'message': 'FCM 토큰이 없습니다.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        user = request.user
        user.fcm_token = fcm_token
        user.save()

        return Response({
            'success': True,
            'message': 'FCM 토큰이 성공적으로 업데이트되었습니다.'
        }, status=status.HTTP_200_OK)