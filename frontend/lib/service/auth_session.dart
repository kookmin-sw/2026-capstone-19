import 'package:shared_preferences/shared_preferences.dart';

class AuthSession {
  static String? token;
  static String? username;

  // 💡 세션 유지 시간 (30분)
  static const int sessionLimit = 30;

  static bool get isLoggedIn => token != null && token!.isNotEmpty;

  // 1. 앱 시작 시 기기에 저장된 토큰과 시각을 불러오는 함수 (main.dart에서 호출)
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('token');
    username = prefs.getString('username');
    print("세션 데이터 로드 완료: $username");
  }

  // 2. 로그인 시 기기에 영구 저장
  static Future<void> save({
    required String newToken,
    required String newUsername,
  }) async {
    token = newToken;
    username = newUsername;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', newToken);
    await prefs.setString('username', newUsername);
    // 로그인한 시점을 마지막 활성 시간으로 기록
    await recordLastActiveTime();
  }

  // 3. 로그아웃 시 기기 데이터 삭제
  static Future<void> clear() async {
    token = null;
    username = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('username');
    await prefs.remove('last_active_time');
  }

  // 4. 앱이 백그라운드로 가거나 꺼질 때 시각 기록
  static Future<void> recordLastActiveTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_active_time', DateTime.now().millisecondsSinceEpoch);
  }

  // 5. 앱이 켜질 때 30분이 지났는지 검사
  static Future<bool> shouldLogout() async {
    final prefs = await SharedPreferences.getInstance();
    final lastActive = prefs.getInt('last_active_time');

    // 토큰이 아예 없으면 이미 로그아웃 상태이므로 무시
    if (token == null || lastActive == null) return false;

    final lastTime = DateTime.fromMillisecondsSinceEpoch(lastActive);
    final now = DateTime.now();
    final diff = now.difference(lastTime).inMinutes;

    print("마지막 활성화로부터 $diff분 경과");

    // 30분 이상 지났으면 true
    return diff >= sessionLimit;
  }
}