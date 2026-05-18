// ============================================================
// lib/utils/routes.dart — 화면 경로 이름 상수 관리
// ============================================================
// 문자열을 직접 쓰면 오타 위험-> 상수로 관리 시 자동완성 + 안전
//
// 사용법:
//   Navigator.pushReplacementNamed(context, AppRoutes.main);
//   Navigator.pushNamed(context, AppRoutes.signup);
// ============================================================

class AppRoutes {
  AppRoutes._(); // 인스턴스 생성 방지

  static const String splash  = '/';         // 스플래시 화면
  static const String login   = '/login';    // 로그인
  static const String signup  = '/signup';   // 회원가입
  static const String main    = '/main';     // 메인 (탭바)
}