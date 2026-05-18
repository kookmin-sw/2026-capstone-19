from firebase_admin import messaging

def send_fcm_notification(user, title, body, data=None):
    """
    실제 FCM 알림을 전송하는 핵심 함수
    """
    # 유저에게 등록된 토큰이 없으면 전송하지 않음
    if not user or not user.fcm_token:
        return None

    # 메시지 객체 생성
    message = messaging.Message(
        notification=messaging.Notification(
            title=title,
            body=body,
        ),
        # 앱 내부 로직(방 이동 등) 처리를 위한 데이터
        data=data or {},
        token=user.fcm_token,
    )

    try:
        response = messaging.send(message)
        print(f"Successfully sent message: {response}")
        return response
    except Exception as e:
        # 토큰이 만료되었거나 잘못된 경우 로그를 남기고 DB를 정리할 수 있습니다.
        print(f"FCM 전송 오류: {e}")
        return None