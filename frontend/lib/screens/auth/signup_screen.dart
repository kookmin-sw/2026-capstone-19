// ============================================================
// lib/screens/auth/signup_screen.dart
// 회원가입 화면 — 옥토모(OCTOMO) 역발상 인증 방식
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/colors.dart';
import '../../service/auth_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();

  // 각 필드 컨트롤러
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _idCtrl    = TextEditingController();
  final _pwCtrl    = TextEditingController();
  final _pwConfCtrl= TextEditingController();

  // 상태 변수들
  String? _selectedGender;      // '남' | '여' | '기타'
  bool _pwVisible     = false;
  bool _pwConfVisible = false;
  bool _isLoading     = false;
  bool _codeSent      = false;  // 인증번호 발급 여부
  bool _phoneVerified = false;  // 본인인증 완료 여부

  static const String _privacyPolicyUrl =
      'https://www.notion.so/TaxiMate-360fb68f0d8980dd9ecde56f7e673f85?source=copy_link';
  static const String _termsOfServiceUrl =
      'https://www.notion.so/TaxiMate-360fb68f0d8980b28d71eb4b600379a1?source=copy_link';
  static const String _locationTermsUrl =
      'https://www.notion.so/TaxiMate-360fb68f0d8980e18e2cdd792512842f?source=copy_link';

  bool _agreePrivacyPolicy = false;
  bool _agreeTermsOfService = false;
  bool _agreeLocationTerms = false;

  bool get _allRequiredTermsAgreed =>
      _agreePrivacyPolicy && _agreeTermsOfService && _agreeLocationTerms;
  
  // 옥토모 역발상 인증 관련 상태
  String _authCode = '';        // 서버에서 발급받은 6자리 코드
  String _octomoNumber = '1666-3538';  // 옥토모 대표번호
  bool _isVerifying = false;    // 인증 확인 진행 중

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _idCtrl.dispose();
    _pwCtrl.dispose();
    _pwConfCtrl.dispose();
    super.dispose();
  }

  // -- 1. 옥토모 역발상 인증 - 코드 발급 --------------------------------
  Future<void> _sendVerificationCode() async {
    if (_phoneCtrl.text.length < 10) {
      _showSnackBar('올바른 전화번호를 입력해주세요.', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await AuthService.sendVerificationCode(phone: _phoneCtrl.text.trim());

      if (result['success'] == true) {
        setState(() {
          _codeSent = true;
          _authCode = result['code'] ?? '';
          _octomoNumber = result['octomoNumber'] ?? '1666-3538';
        });
        _showSnackBar('인증 코드가 발급되었습니다. $_octomoNumber로 SMS를 발송해주세요.');
      } else {
        _showSnackBar(result['message'] ?? '코드 발급에 실패했습니다.', isError: true);
      }
    } catch (e) {
      _showSnackBar('오류가 발생했습니다: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // -- 2. 옥토모 역발상 인증 - SMS 앱 열기 --------------------------------
  Future<void> _openSmsApp() async {
    if (_authCode.isEmpty) {
      _showSnackBar('인증 코드가 없습니다. 인증번호를 먼저 발급받아주세요.', isError: true);
      return;
    }

    // url_launcher용 번호는 하이픈 제거 (16663538)
    final Uri smsUri = Uri.parse('sms:16663538?body=$_authCode');
    
    try {
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
      } else {
        _showSnackBar('문자 앱을 열 수 없습니다. 수동으로 $_octomoNumber에 코드 $_authCode를 보내주세요.', isError: true);
      }
    } catch (e) {
      _showSnackBar('문자 앱 실행 중 오류가 발생했습니다: $e', isError: true);
    }
  }

  // -- 2. 옥토모 역발상 인증 - SMS 발송 여부 확인 --------------------------------
  Future<void> _verifyCode() async {
    setState(() => _isVerifying = true);

    try {
      final result = await AuthService.verifyCode(phone: _phoneCtrl.text.trim());

      if (result['success'] == true && result['verified'] == true) {
        setState(() {
          _phoneVerified = true;
        });
        _showSnackBar('본인인증이 완료되었습니다.');
      } else {
        _showSnackBar(result['message'] ?? '인증 확인에 실패했습니다. SMS를 정확히 발송했는지 확인해주세요.', isError: true);
      }
    } catch (e) {
      _showSnackBar('인증 확인 중 오류가 발생했습니다: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _openPolicyUrl(String url) async {
    final uri = Uri.parse(url);

    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!mounted) return;

      if (!opened) {
        _showSnackBar('약관 페이지를 열 수 없습니다.', isError: true);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('약관 페이지를 여는 중 오류가 발생했습니다.', isError: true);
      }
    }
  }


  // -- 3. 회원가입 처리 --------------------------------
  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedGender == null) {
      _showSnackBar('성별을 선택해주세요.', isError: true);
      return;
    }

    if (!_phoneVerified) {
      _showSnackBar('본인인증을 완료해주세요.', isError: true);
      return;
    }

    if (!_allRequiredTermsAgreed) {
      _showSnackBar('필수 약관에 모두 동의해주세요.', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await AuthService.signup(
        name: _nameCtrl.text.trim(),
        username: _idCtrl.text.trim(),
        gender: _selectedGender!,
        phone: _phoneCtrl.text.trim(),
        password: _pwCtrl.text,
      );

      if (result['success'] == true) {
        if (mounted) {
          _showSnackBar('회원가입이 완료되었습니다!');
          Navigator.pop(context);
        }
      } else {
        if (mounted) _showSnackBar(result['message'] ?? '회원가입에 실패했습니다.', isError: true);
      }
    } catch (e) {
      if (mounted) _showSnackBar('오류가 발생했습니다: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // -- 스낵바 & 헬퍼 함수 ------------------------------------------
  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.red : AppColors.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('회원가입', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.secondary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // 1. 이름
              _sectionLabel('이름', Icons.badge_outlined),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameCtrl,
                decoration: _inputDeco(hint: '실명을 입력하세요'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return '이름을 입력해주세요.';
                  if (v.trim().length < 2) return '이름은 2자 이상이어야 합니다.';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // 2. 성별
              _sectionLabel('성별', Icons.wc_outlined),
              const SizedBox(height: 8),
              Row(
                children: ['남', '여'].map((g) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedGender = g),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _selectedGender == g ? AppColors.primary : AppColors.bg,
                          border: Border.all(
                            color: _selectedGender == g ? AppColors.primary : AppColors.border,
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(g,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14,
                              color: _selectedGender == g ? Colors.white : AppColors.gray,
                            )),
                      ),
                    ),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 20),

              // 3. 전화번호 + 본인인증
              _sectionLabel('전화번호 & 본인인증', Icons.phone_outlined),
              const SizedBox(height: 6),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 11,
                      decoration: _inputDeco(hint: '01012345678').copyWith(counterText: ''),
                      enabled: !_phoneVerified,
                      validator: (v) {
                        if (v == null || v.isEmpty) return '전화번호를 입력해주세요.';
                        if (v.length < 10) return '올바른 전화번호를 입력해주세요.';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _phoneVerified ? AppColors.gray : AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      onPressed: _phoneVerified ? null : _sendVerificationCode,
                      child: Text(_phoneVerified ? '완료' : (_codeSent ? '재전송' : '인증번호\n받기'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),

              if (_codeSent && !_phoneVerified) ...[
                const SizedBox(height: 16),

                // 코드 표시 영역
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        '인증 코드',
                        style: TextStyle(fontSize: 13, color: AppColors.gray, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primary, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: _authCode.characters.map((char) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                            ),
                            child: Text(
                              char,
                              style: const TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                                color: AppColors.secondary,
                              ),
                            ),
                          )).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 메시지 작성하기 버튼
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: const BorderSide(color: AppColors.primary, width: 1.5),
                            ),
                            elevation: 0,
                          ),
                          onPressed: _openSmsApp,
                          icon: const Icon(Icons.send, size: 18),
                          label: const Text(
                            '인증번호 보내기',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // SMS 안내 영역
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFC107)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline, color: Color(0xFF5D4E37), size: 18),
                          const SizedBox(width: 8),
                          Text(
                            '$_octomoNumber로 위 코드를 문자로 보내주세요',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF5D4E37),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '• 보내기 버튼을 눌러 인증기관으로 메시지를 수정 없이 그대로 발송하셔야 합니다.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF5D4E37), height: 1.5),
                      ),
                      const Text(
                        '• 인증 메시지 발송 후, 아래 인증하기 버튼을 눌러 진행해 주세요.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF5D4E37), height: 1.5),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 인증 확인 버튼
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: _isVerifying ? null : _verifyCode,
                    child: _isVerifying
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            '인증 확인',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
              ],

              if (_phoneVerified) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: AppColors.primary, size: 16),
                      SizedBox(width: 6),
                      Text('본인인증이 완료되었습니다.',
                          style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // 4. 아이디
              _sectionLabel('아이디', Icons.alternate_email),
              const SizedBox(height: 6),
              TextFormField(
                controller: _idCtrl,
                decoration: _inputDeco(hint: '영문, 숫자 조합 4~20자'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return '아이디를 입력해주세요.';
                  if (v.trim().length < 4) return '아이디는 4자 이상이어야 합니다.';
                  if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(v.trim())) return '영문, 숫자, 밑줄(_)만 사용 가능합니다.';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // 5. 비밀번호
              _sectionLabel('비밀번호', Icons.lock_outline),
              const SizedBox(height: 6),
              TextFormField(
                controller: _pwCtrl,
                obscureText: !_pwVisible,
                decoration: _inputDeco(
                  hint: '영문+숫자 조합 8자 이상',
                  suffix: IconButton(
                    icon: Icon(_pwVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: AppColors.gray, size: 20),
                    onPressed: () => setState(() => _pwVisible = !_pwVisible),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return '비밀번호를 입력해주세요.';
                  if (v.length < 8) return '비밀번호는 8자 이상이어야 합니다.';
                  if (!RegExp(r'^(?=.*[a-zA-Z])(?=.*\d)').hasMatch(v)) return '영문과 숫자만 입력해주세요.';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _pwConfCtrl,
                obscureText: !_pwConfVisible,
                decoration: _inputDeco(
                  hint: '비밀번호를 한 번 더 입력하세요',
                  suffix: IconButton(
                    icon: Icon(_pwConfVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: AppColors.gray, size: 20),
                    onPressed: () => setState(() => _pwConfVisible = !_pwConfVisible),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return '비밀번호 확인을 입력해주세요.';
                  if (v != _pwCtrl.text) return '비밀번호가 일치하지 않습니다.';
                  return null;
                },
              ),
              const SizedBox(height: 24),

              _sectionLabel('약관 동의', Icons.description_outlined),
              const SizedBox(height: 8),

              _agreementTile(
                value: _agreePrivacyPolicy,
                title: '개인정보 처리방침 동의',
                url: _privacyPolicyUrl,
                onChanged: (v) {
                  setState(() => _agreePrivacyPolicy = v ?? false);
                },
              ),
              const SizedBox(height: 8),

              _agreementTile(
                value: _agreeTermsOfService,
                title: '서비스 이용약관 동의',
                url: _termsOfServiceUrl,
                onChanged: (v) {
                  setState(() => _agreeTermsOfService = v ?? false);
                },
              ),
              const SizedBox(height: 8),

              _agreementTile(
                value: _agreeLocationTerms,
                title: '위치기반 서비스 약관 동의',
                url: _locationTermsUrl,
                onChanged: (v) {
                  setState(() => _agreeLocationTerms = v ?? false);
                },
              ),

              const SizedBox(height: 24),

              // 회원가입 버튼
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: (_isLoading || !_allRequiredTermsAgreed) ? null : _handleSignup,
                  child: _isLoading
                      ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : const Text('회원가입 완료', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 16),

              // 로그인으로 돌아가기
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(foregroundColor: AppColors.gray),
                  child: const Text('이미 계정이 있으신가요? 로그인',
                      style: TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // 공통 위젯 헬퍼
  Widget _sectionLabel(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.secondary)),
      ],
    );
  }

  Widget _agreementTile({
    required bool value,
    required String title,
    required String url,
    required ValueChanged<bool?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.secondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _openPolicyUrl(url),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(44, 32),
            ),
            child: const Text(
              '보기',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }


  InputDecoration _inputDeco({required String hint, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: AppColors.gray),
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