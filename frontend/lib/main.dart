// ============================================================
// lib/main.dart
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/auth/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/tabs/home_tab.dart';
import 'screens/tabs/matching_tab.dart';
import 'screens/tabs/active_tab.dart';
import 'screens/tabs/message_tab.dart';
import 'screens/tabs/myPage_tab.dart';
import 'service/auth_session.dart';
import 'service/trip_service.dart';
import 'utils/colors.dart';
import 'utils/evaluation_helper.dart';
import 'utils/routes.dart';
import 'service/notification_service.dart';
import 'service/auth_session.dart';

void main() async {
  // 1. Flutter 엔진 초기화
  WidgetsFlutterBinding.ensureInitialized();

  // 2. 서비스 초기화
  await NotificationService.init();
  await AuthSession.load();

  // 3. 카카오맵 SDK 초기화 (웹에서는 제외)
  if (!kIsWeb) {
    AuthRepository.initialize(
      appKey: '2c89ba1eee07b01fbfb0d1ca3220eff2',
      baseUrl: 'https://localhost',
    );
  }

  // 4. 앱 실행 (TaxiMateApp 하나만 남깁니다)
  runApp(const TaxiMateApp());
}

// 앱 최상위 위젯
class TaxiMateApp extends StatelessWidget {
  const TaxiMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TaxiMate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          surface: Colors.white,
          onPrimary: Colors.white,
          onSurface: AppColors.secondary,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.secondary,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        scaffoldBackgroundColor: AppColors.bg,
        cardTheme: CardThemeData(
          color: Colors.white, elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
      ),
      initialRoute: AppRoutes.splash, // 스플래시 화면부터 시작
      routes: {
        AppRoutes.splash: (_) => const SplashScreen(),
        AppRoutes.login:  (_) => const LoginScreen(),
        AppRoutes.signup: (_) => const SignupScreen(),
        AppRoutes.main:   (_) => const MainScreen(),
      },
    );
  }
}

// 메인 화면 (StatefulWidget으로 탭 구조 관리)
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

// 메인 화면 상태 관리 클래스
class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingEvaluations();
    });
  }

  Future<void> _checkPendingEvaluations() async {
    final token = AuthSession.token ?? '';
    if (token.isEmpty || !mounted) return;

    try {
      final rooms = await TripService.getChatRooms(token: token);
      final prefs = await SharedPreferences.getInstance();
      final evaluated =
          prefs.getStringList(EvaluationHelper.evaluatedRoomsKey) ?? [];

      for (final item in rooms) {
        if (item is! Map) continue;

        final map = Map<String, dynamic>.from(item);
        final isLeader = map['is_leader'] == true;
        final notice = map['pinned_notice']?.toString() ?? '';
        final roomIdRaw = map['id'];
        final roomId = roomIdRaw is int
            ? roomIdRaw
            : int.tryParse(roomIdRaw?.toString() ?? '') ?? 0;

        if (roomId == 0) continue;
        if (isLeader) continue;
        if (!notice.contains('정산이 완료되었습니다')) continue;
        if (evaluated.contains(roomId.toString())) continue;

        if (!mounted) return;

        final tripIdRaw = map['trip_id'];
        final tripId = tripIdRaw is int
            ? tripIdRaw
            : int.tryParse(tripIdRaw?.toString() ?? '') ?? 0;
        final roomName = map['trip_title']?.toString() ?? '채팅방';

        await EvaluationHelper.showGlobalEvaluationDialog(
          context: context,
          roomId: roomId,
          tripId: tripId,
          roomName: roomName,
        );
        break;
      }
    } catch (e) {
      debugPrint('미완료 평가 확인 실패: $e');
    }
  }

  // 각 탭 화면 리스트
  List<Widget> get _screens => [
    HomeTab(
      onTabChange: (i) => setState(() => _selectedIndex = i),
      onGoToCreate: () => setState(() => _selectedIndex = 1),
    ),
    MatchingTab(onGoHome: () => setState(() => _selectedIndex = 0)),
    const ActiveTab(),
    const MessageTab(),
    const MyPageTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ), // 여러 탭 화면 유지하면서 현재 탭만 출력
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed, // 탭 네비게이션 바
        currentIndex: _selectedIndex, // 현재 선택된 탭 인덱스
        onTap: (i) => setState(() => _selectedIndex = i),
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.gray,
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        elevation: 12,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: '홈',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.location_on_outlined),
            activeIcon: Icon(Icons.location_on),
            label: '매칭',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.directions_car_outlined),
            activeIcon: Icon(Icons.directions_car),
            label: '이용 중',
          ),
          BottomNavigationBarItem(
            icon: ValueListenableBuilder<bool>(
              valueListenable: ChatTabBadgeController.hasNewChat,
              builder: (context, hasNewChat, child) {
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.chat_bubble_outline),
                    if (hasNewChat)
                      Positioned(
                        right: -7,
                        top: -5,
                        child: Container(
                          width: 16,
                          height: 16,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Text(
                            'N',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            activeIcon: ValueListenableBuilder<bool>(
              valueListenable: ChatTabBadgeController.hasNewChat,
              builder: (context, hasNewChat, child) {
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.chat_bubble),
                    if (hasNewChat)
                      Positioned(
                        right: -7,
                        top: -5,
                        child: Container(
                          width: 16,
                          height: 16,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Text(
                            'N',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            label: '채팅',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: '내정보',
          ),
        ],
      ),
    );
  }
}