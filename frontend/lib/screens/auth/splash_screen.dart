// ============================================================
// lib/screens/auth/splash_screen.dart
// 스플래시 화면 — 앱 첫 실행 시 로딩 후 로그인 화면으로 이동
// ============================================================
import 'package:flutter/material.dart';
import '../../utils/colors.dart';
import '../../utils/routes.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {

  // 애니메이션 컨트롤러 — 로고 fade-in 효과
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();

    // 애니메이션 설정 (1.2초 동안 실행)
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnim  = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0, 0.6, curve: Curves.easeOut)),
    );
    _scaleAnim = Tween<double>(begin: 0.8, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0, 0.6, curve: Curves.easeOut)),
    );

    _controller.forward();

    // 2.5초 후 로그인 화면으로 이동
    // 실제 앱에서는 여기서 Firebase Auth 로그인 상태를 확인하고
    // 로그인 됐으면 main으로, 아니면 login으로 분기
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;

      // pushReplacementNamed: 스플래시를 스택에서 제거하고 이동
      // (뒤로가기 버튼으로 스플래시로 돌아올 수 없게)
      Navigator.pushReplacementNamed(context, AppRoutes.login);

      // TODO: Firebase Auth 연동 시 아래처럼 분기
      // final user = FirebaseAuth.instance.currentUser;
      // final route = user != null ? AppRoutes.main : AppRoutes.login;
      // Navigator.pushReplacementNamed(context, route);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 스플래시는 브랜드 그린 배경
      backgroundColor: AppColors.primary,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, __) => FadeTransition(
            opacity: _fadeAnim,
            child: ScaleTransition(
              scale: _scaleAnim,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 앱 아이콘 (실제로는 Image.asset('assets/icon.png')-> 나중에 필요 시 수정)
                  Container(
                    width: 96, height: 96,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Center(
                      child: Text('🚖', style: TextStyle(fontSize: 52)),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 로고 텍스트
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 48,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w900,
                      ),
                      children: [
                        TextSpan(text: 'TAXI', style: TextStyle(color: Colors.white)),
                        TextSpan(text: 'MATE', style: TextStyle(color: Color(0xFFFFD166))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Ride Together, Save Together',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 60),

                  // 로딩 인디케이터
                  SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white.withOpacity(0.6),
                      strokeWidth: 2.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}