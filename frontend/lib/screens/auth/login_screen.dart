// ============================================================
// lib/screens/auth/login_screen.dart
// 로그인 화면 — 아이디 + 비밀번호
// ============================================================
import '../../service/auth_session.dart';
import 'package:flutter/material.dart';
import '../../utils/colors.dart';
import '../../utils/routes.dart';
import 'package:taximate/service/auth_service.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {

  // GlobalKey<FormState>: Form 위젯의 유효성 검사를 제어하는 키
  // _formKey.currentState!.validate() 호출 시 각 TextFormField의 validator 실행
  final _formKey = GlobalKey<FormState>();

  // TextEditingController: 입력 필드의 값을 읽고 쓰는 컨트롤러
  final _idCtrl  = TextEditingController();
  final _pwCtrl  = TextEditingController();

  bool _pwVisible = false; // 비밀번호 표시/숨기기 토글
  bool _isLoading = false; // 로그인 버튼 로딩 상태

  @override
  void dispose() {
    // 화면이 사라질 때 컨트롤러 메모리 해제 (필수!)
    _idCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  // -- 로그인 처리 ----------------------------------------------------
  Future<void> _handleLogin() async {
    // 유효성 검사 실패 시 early return
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    // api 호출
    final result = await AuthService.login(
     username: _idCtrl.text.trim(),
     password: _pwCtrl.text.trim(),
    );


    setState(() => _isLoading = false);

    if (result['success'] == true) {
      final token = result['token']?.toString() ?? '';
      final username = result['username']?.toString() ?? '';

      if (token.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('로그인 토큰을 받지 못했습니다.'),
            backgroundColor: AppColors.red,
          ),
        );
        return;
      }

      AuthSession.save(
        newToken: token,
        newUsername: username,
      );

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.main);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? '로그인에 실패했습니다.'),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // resizeToAvoidBottomInset: 키보드가 올라올 때 화면이 밀려 올라가도록
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 56),

                // 로고 영역
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 72, height: 72,
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: const Center(child: Text('🚖', style: TextStyle(fontSize: 38))),
                      ),
                      const SizedBox(height: 16),
                      RichText(text: const TextSpan(
                        style: TextStyle(fontSize: 32, letterSpacing: 2, fontWeight: FontWeight.w900),
                        children: [
                          TextSpan(text: 'TAXI', style: TextStyle(color: AppColors.secondary)),
                          TextSpan(text: 'MATE', style: TextStyle(color: AppColors.primary)),
                        ],
                      )),
                      const SizedBox(height: 8),
                      const Text('함께 타고, 함께 아끼세요',
                          style: TextStyle(fontSize: 13, color: AppColors.gray, letterSpacing: 0.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 48),

                // 로그인 폼
                const Text('로그인', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.secondary)),
                const SizedBox(height: 20),

                // 아이디 입력
                _buildLabel('아이디'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _idCtrl,
                  keyboardType: TextInputType.text,
                  decoration: _inputDeco(hint: '아이디를 입력하세요', icon: Icons.person_outline),
                  // validator: 로그인 버튼 클릭 시 자동 실행됨
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return '아이디를 입력해주세요.';
                    return null; // null = 유효함
                  },
                ),
                const SizedBox(height: 14),

                // 비밀번호 입력
                _buildLabel('비밀번호'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _pwCtrl,
                  // obscureText: true면 입력값이 ●●● 로 표시됨
                  obscureText: !_pwVisible,
                  decoration: _inputDeco(
                    hint: '비밀번호를 입력하세요',
                    icon: Icons.lock_outline,
                    suffix: IconButton(
                      icon: Icon(_pwVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: AppColors.gray, size: 20),
                      onPressed: () => setState(() => _pwVisible = !_pwVisible),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return '비밀번호를 입력해주세요.';
                    if (v.length < 6) return '비밀번호는 6자 이상이어야 합니다.';
                    return null;
                  },
                ),
                const SizedBox(height: 28),

                // 로그인 버튼
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    // 로딩 중이면 버튼 비활성화
                    onPressed: _isLoading ? null : _handleLogin,
                    child: _isLoading
                        ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : const Text('로그인', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 20),

                // 회원가입 링크
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('아직 계정이 없으신가요?', style: TextStyle(fontSize: 13, color: AppColors.gray)),
                    TextButton(
                      // pushNamed: 회원가입 화면을 스택에 추가 (뒤로가기로 로그인 화면으로 돌아올 수 있음)
                      onPressed: () => Navigator.pushNamed(context, AppRoutes.signup),
                      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                      child: const Text('회원가입', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 공통 위젯 헬퍼
  Widget _buildLabel(String text) {
    return Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.secondary));
  }

  InputDecoration _inputDeco({required String hint, required IconData icon, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 14, color: AppColors.gray),
      prefixIcon: Icon(icon, color: AppColors.gray, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.bg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.red)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.red, width: 1.5)),
    );
  }
}