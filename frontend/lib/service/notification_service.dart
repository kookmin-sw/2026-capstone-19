// lib/service/notification_service.dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart'; // 🌟 추가됨
import 'package:firebase_messaging/firebase_messaging.dart';
import 'trip_service.dart';

// 🌟 추가 1: 앱이 백그라운드(꺼진 상태)일 때 푸시를 처리하는 최상단 함수
// 반드시 클래스 바깥(최상단)에 위치해야 합니다.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("백그라운드 메시지 수신: ${message.messageId}");
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  // 🌟 추가 2: 현재 사용자가 들어가 있는 채팅방 ID (알림 중복 방지용)
  static int? currentActiveRoomId;

  static Future<void> init() async {
    // ---- 기존 로컬 알림 세팅 유지 ----
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // v21 버전에 맞는 초기화 문법
    await _plugin.initialize(initSettings);

    // ---- 🌟 추가 3: Firebase 푸시 알림(FCM) 세팅 시작 ----
    await Firebase.initializeApp();

    // 백그라운드 핸들러 등록
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 푸시 알림 권한 요청 (특히 iOS에서 필수)
    NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      // 서버(Django)에 보낼 기기 고유 토큰 발급
      String? fcmToken = await FirebaseMessaging.instance.getToken();
      print("🔑 내 기기 FCM Token: $fcmToken");
      // TODO: 나중에 로그인 성공 시 이 토큰을 백엔드로 보내는 API 호출을 연결하세요.

      // 앱을 켜두고(Foreground) 있을 때 푸시가 오면 가로채기
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _handleForegroundMessage(message);
      });
    }
  }

  // 🌟 추가 4: 앱 켜져 있을 때 채팅 알림 띄우기 조건 처리
  static void _handleForegroundMessage(RemoteMessage message) {
    // 백엔드에서 보낼 때 data 영역에 'room_id': '123' 형태로 보낸다고 가정
    final String? roomIdStr = message.data['room_id'];
    final int? roomId = int.tryParse(roomIdStr ?? '');
    final String? type = message.data['type'];


    if (type == 'TRIP_JOIN' || type == 'TRIP_LEAVE' || type == 'TRIP_DELETED') {
      TripService.notifyTripsChanged();
    }
    // 💡 핵심: 지금 메시지가 온 채팅방을 내가 켜놓고 보고 있다면? -> 알림 안 띄움!
    if (roomId != null && roomId == currentActiveRoomId) {
      return;
    }

    // 다른 화면을 보고 있거나, 다른 채팅방에 있다면? -> 상단 팝업 알림 띄움!
    _showChatNotification(
      title: message.notification?.title ?? 'Crescit',
      body: message.notification?.body ?? '새로운 메시지가 도착했습니다.',
    );
  }

  // 🌟 추가 5: 일반 채팅 알림 팝업 (기존 고정 알림과 별개)
  static Future<void> _showChatNotification({
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'chat_channel', // 기존 active_ride_channel 과 다른 채널 ID 사용
      '채팅 알림',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    // 채팅 알림은 고유한 ID(밀리초)를 줘서 여러 개가 쌓이게 만듭니다.
    await _plugin.show(
      DateTime.now().millisecond,
      title,
      body,
      platformDetails,
    );
  }

  // ---- 아래는 기존에 작성하신 택시 이용 중 고정 알림 코드 그대로 유지 ----
  static Future<void> showOngoingRide({
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'active_ride_channel',
      '이용 중 상태 알림',
      channelDescription: '택시 이용 중 화면에 고정되는 알림입니다.',
      importance: Importance.max,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      playSound: false,
      enableVibration: false,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    await _plugin.show(
      0, // ID 0번 고정
      title,
      body,
      platformDetails,
    );
  }

  static Future<void> cancelOngoingRide() async {
    await _plugin.cancel(0);
  }
}