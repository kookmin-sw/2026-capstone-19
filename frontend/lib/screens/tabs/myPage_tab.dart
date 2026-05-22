import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../auth/login_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/colors.dart';
import '../../service/auth_service.dart';
import '../../service/auth_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../service/trip_service.dart';
import 'active_tab.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

// ============================================================
// 공통 컴포넌트: AppBar
// ============================================================
AppBar _appBar(String title) => AppBar(
      title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      backgroundColor: Colors.white,
      foregroundColor: AppColors.secondary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border)),
    );

// ============================================================
// 1. 마이페이지 탭 (메인)
// ============================================================
class MyPageTab extends StatefulWidget {
  final int refreshSignal;

  const MyPageTab({
    super.key,
    this.refreshSignal = 0,
  });

  @override
  State<MyPageTab> createState() => _MyPageTabState();
}

class _MyPageTabState extends State<MyPageTab> {
  File? _profileImage;
  final ImagePicker _picker = ImagePicker();
  Future<Map<String, dynamic>>? _profileFuture;

  @override
  void initState() {
    super.initState();
    if (AuthSession.isLoggedIn) {
      _profileFuture = AuthService.getProfile();
    }
  }

  @override
  void didUpdateWidget(covariant MyPageTab oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.refreshSignal != widget.refreshSignal && AuthSession.isLoggedIn) {
      _refreshProfile();
    }
  }

  // 1. 누락되었던 닫는 괄호를 추가했습니다.
  void _refreshProfile() {
    if (AuthSession.isLoggedIn) {
      setState(() {
        _profileFuture = AuthService.getProfile();
      });
    }
  }

  // 2. 중복되었던 _pickImage를 하나로 통합했습니다.
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
          source: source,
          imageQuality: 80,
          maxWidth: 512,
          maxHeight: 512
      );

      if (picked != null) {
        final result = await AuthService.updateProfileImage(File(picked.path));

        if (result['success'] == true) {
          setState(() {
            _profileImage = File(picked.path);
          });
          _refreshProfile(); // 서버 데이터를 다시 불러와 UI 갱신
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(result['message'] ?? '프로필 사진이 변경되었습니다.'))
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('사진을 처리하는 중 오류가 발생했습니다.'))
        );
      }
    }
  }

  List<_MenuItem> _getDynamicMenus(Map<String, dynamic> userData) {
    final String score = userData['trust_score']?.toString() ?? '36.5';
    final int count = int.tryParse('${userData['history_count'] ?? 0}') ?? 0;

    return [
      _MenuItem(icon: Icons.verified_user_outlined, label: '인증 관리', sub: '본인 및 신원 인증', screen: const _AuthScreen()),
      _MenuItem(icon: Icons.star_outline, label: '회원 매너 점수 관리', sub: '현재 $score점', screen: const _MannerScreen()),
      _MenuItem(icon: Icons.local_taxi_outlined, label: '이용 내역', sub: '총 $count건', screen: const HistoryScreen()),
      _MenuItem(icon: Icons.settings_outlined, label: '설정', sub: '알림, 약관, 버전 정보', screen: const SettingsScreen()),
      _MenuItem(icon: Icons.headset_mic_outlined, label: '고객지원', sub: '문의 및 전화 상담', screen: const SupportScreen()),
      _MenuItem(icon: Icons.flag_outlined, label: '신고하기', sub: '부적절한 이용자 신고', screen: const _ReportScreen(), color: AppColors.red),
      _MenuItem(icon: Icons.logout, label: '로그아웃', sub: null, screen: null, color: AppColors.red),
    ];
  }

  void _showImagePickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
              const Align(alignment: Alignment.centerLeft, child: Text('프로필 사진 변경', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.secondary))),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.photo_library_outlined, color: AppColors.primary, size: 22)),
                title: const Text('갤러리에서 선택', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text('앨범에서 사진을 가져옵니다', style: TextStyle(fontSize: 11, color: AppColors.gray)),
                onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); },
              ),
              const Divider(color: AppColors.border, height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.camera_alt_outlined, color: Color(0xFF4A6FFF), size: 22)),
                title: const Text('카메라로 촬영', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text('지금 바로 사진을 촬영합니다', style: TextStyle(fontSize: 11, color: AppColors.gray)),
                onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); },
              ),
            ],
          ),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    if (_profileFuture == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 48, color: AppColors.gray),
              const SizedBox(height: 16),
              const Text('로그인이 필요한 서비스입니다.', style: TextStyle(color: AppColors.secondary)),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: () => Navigator.pushNamed(context, '/login'), child: const Text('로그인하러 가기')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: FutureBuilder<Map<String, dynamic>>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data?['success'] == false) return const Center(child: Text('데이터 로딩 실패'));
          final userData = snapshot.data?['data'];
          if (userData == null) return const Center(child: Text('프로필 데이터를 불러올 수 없습니다.'));

          final currentMenus = _getDynamicMenus(userData);

          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildProfileHeader(userData),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(children: currentMenus.map((m) => _buildMenuItem(context, m)).toList()),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileHeader(Map<String, dynamic> userData) {
    final String realName = userData['user_real_name'] ?? '이름 없음';
    final String username = userData['username'] ?? 'unknown';
    final String trustScore = userData['trust_score']?.toString() ?? '36.5';
    final int tripCount = int.tryParse('${userData['history_count'] ?? 0}') ?? 0;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
      child: Column(
        children: [
          GestureDetector(
            onTap: _showImagePickerSheet,
            child: Stack(
              children: [
                Container(
                  width: 84, height: 84,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.bg, border: Border.all(color: AppColors.border, width: 2)),
                  child: ClipOval(
                    child: userData['profile_img_url'] != null
                        ? Image.network(userData['profile_img_url'], fit: BoxFit.cover)
                        : const Icon(Icons.person, color: AppColors.gray, size: 48),
                  ),
                ),
                Positioned(
                  right: 0, bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(realName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.secondary)),
          const SizedBox(height: 4),
          Text('@$username', style: const TextStyle(fontSize: 12, color: AppColors.gray)),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _tag('인증됨 ✓'),
            _tag('⭐ $trustScore', color: AppColors.accent, bg: const Color(0xFFFFF8E6)),
            _tag('탑승 $tripCount회'),
          ]),
          Container(
            margin: const EdgeInsets.only(top: 20),
            padding: const EdgeInsets.only(top: 16),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
            child: Row(children: [
              _stat('$tripCount회', '총 탑승'),
              Container(width: 1, height: 36, color: AppColors.border),
              _stat('$trustScore점', '매너점수', color: AppColors.accent),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _stat(String val, String label, {Color color = AppColors.primary}) {
    return Expanded(child: Column(children: [
      Text(val, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 11, color: AppColors.gray)),
    ]));
  }

  Widget _tag(String t, {Color color = AppColors.primary, Color bg = AppColors.primaryLight}) =>
      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
          child: Text(t, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)));

  Widget _buildMenuItem(BuildContext context, _MenuItem menu) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              if (menu.label == '로그아웃') {
                _showLogoutDialog(context);
                return;
              }

              if (menu.screen != null) {
                // 1. 화면 이동 후 사용자가 뒤로가기를 누를 때까지 기다립니다.
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => menu.screen!)
                );

                // 2. 돌아오자마자 최신 정보를 다시 가져옵니다.
                // _refreshProfile() 내부에 setState와 _profileFuture 갱신 로직이 들어있다면
                // 아래처럼 한 줄만 써주면 됩니다.
                _refreshProfile();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: menu.color != null
                        ? menu.color!.withOpacity(0.1)
                        : AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(menu.icon,
                      color: menu.color ?? AppColors.primary, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(menu.label,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: menu.color ?? AppColors.secondary)),
                    if (menu.sub != null)
                      Text(menu.sub!,
                          style:
                              const TextStyle(fontSize: 11, color: AppColors.gray)),
                  ],
                )),
                const Icon(Icons.chevron_right, color: AppColors.border, size: 22),
              ]),
            ),
          ),
        ),
      );
    }

  void _showLogoutDialog(BuildContext context) {
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('로그아웃', style: TextStyle(fontWeight: FontWeight.w700)),
      content: const Text('정말 로그아웃 하시겠어요?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white, elevation: 0),
            onPressed: () async {
              Navigator.pop(context);
              await AuthService.logout();
// 🌟 3. 바로 여기에 추가! 화면 넘어가기 전에 데이터 비우기
              globalActiveRideState.reset();
              if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
            }, child: const Text('로그아웃')),
      ],
    ));
  }
}

// ============================================================
// 2. 이용 내역 화면 (History)
// ============================================================
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _histories = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    try {
      final history = await AuthService.getTripHistory();

      if (!mounted) return;

      setState(() {
        _histories = history;
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = '이용 내역을 불러오는 데 실패했습니다: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthSession.isLoggedIn) {
      return Scaffold(
        appBar: _appBar('이용 내역'),
        body: const Center(child: Text('로그인이 필요합니다.')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _appBar('이용 내역'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchHistory,
              child: _error != null
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        const SizedBox(height: 180),
                        Center(
                          child: Text(
                            _error!,
                            style: const TextStyle(color: AppColors.red),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    )
                  : _histories.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          children: const [
                            SizedBox(height: 180),
                            Center(
                              child: Text(
                                '완료된 이용 내역이 없습니다.',
                                style: TextStyle(color: AppColors.gray),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: _histories.length,
                          itemBuilder: (_, i) => _buildHistoryCard(_histories[i]),
                        ),
            ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> h) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
            child: Row(children: [
              const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.gray),
              const SizedBox(width: 6),
              Text(h['date'] ?? '', style: const TextStyle(fontSize: 12, color: AppColors.gray)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(100)),
                child: Text(h['status'] ?? '완료', style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(h['team'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.secondary)),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.location_on, size: 14, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text(h['dept'] ?? '', style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('→', style: TextStyle(color: AppColors.textSub, fontWeight: FontWeight.w700))),
                  Text(h['dest'] ?? '', style: const TextStyle(fontSize: 12, color: AppColors.secondary)),
                ]),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Text('내 부담액', style: const TextStyle(fontSize: 12, color: AppColors.gray)),
                    const Spacer(),
                    Text('₩${h['my'] ?? '0'}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary)),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 3. 설정 화면 (Settings)
// ============================================================
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _pushAlarm = true;
  bool _isUpdatingPushAlarm = false;

  static const String _pushAlarmPrefsKey = 'push_alarm_enabled';

  @override
  void initState() {
    super.initState();
    _loadPushAlarmSetting();
  }

  Future<void> _loadPushAlarmSetting() async {
    final prefs = await SharedPreferences.getInstance();
    final savedValue = prefs.getBool(_pushAlarmPrefsKey);

    if (!mounted) return;

    setState(() {
      _pushAlarm = savedValue ?? true;
    });
  }

  Future<void> _handlePushAlarmChanged(bool value) async {
    if (_isUpdatingPushAlarm) return;

    final previousValue = _pushAlarm;

    setState(() {
      _pushAlarm = value;
      _isUpdatingPushAlarm = true;
    });

    try {
      final token = AuthSession.token ?? '';

      if (token.isEmpty) {
        throw Exception('로그인이 필요합니다.');
      }

      String? fcmToken;

      if (value) {
        final settings = await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );

        final isAuthorized =
            settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;

        if (!isAuthorized) {
          throw Exception('기기 알림 권한이 허용되지 않았습니다.');
        }

        fcmToken = await FirebaseMessaging.instance.getToken();

        if (fcmToken == null || fcmToken.isEmpty) {
          throw Exception('FCM 토큰을 가져오지 못했습니다.');
        }
      }

      final result = await AuthService.updateFcmToken(
        token: token,
        fcmToken: value ? fcmToken : null,
      );

      if (result['success'] != true) {
        throw Exception(result['message'] ?? '푸시 알림 설정 변경에 실패했습니다.');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_pushAlarmPrefsKey, value);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? '푸시 알림을 켰습니다.' : '푸시 알림을 껐습니다.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _pushAlarm = previousValue;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('푸시 알림 설정 변경 실패: $e'),
        ),
      );
    } finally {
      if (!mounted) return;

      setState(() {
        _isUpdatingPushAlarm = false;
      });
    }
  }

  static const String _privacyPolicyUrl =
      'https://www.notion.so/TaxiMate-360fb68f0d8980dd9ecde56f7e673f85?source=copy_link';
  static const String _termsOfServiceUrl =
      'https://www.notion.so/TaxiMate-360fb68f0d8980b28d71eb4b600379a1?source=copy_link';
  static const String _locationTermsUrl =
      'https://www.notion.so/TaxiMate-360fb68f0d8980e18e2cdd792512842f?source=copy_link';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _appBar('설정'),
      body: ListView(
        children: [
          _sectionTitle('🔔 알림 설정'),
          _switchTile(
            '푸쉬 알림 동의',
            '채팅, 참여, 정산 등 서비스 알림 수신',
            _pushAlarm,
            (v) {
              _handlePushAlarmChanged(v);
            },
          ),
          _sectionTitle('📄 약관 및 정책'),
          _navTile(
            '개인정보 처리방침',
            null,
            () => _openPolicyUrl(_privacyPolicyUrl),
          ),
          _navTile(
            '서비스 이용약관',
            null,
            () => _openPolicyUrl(_termsOfServiceUrl),
          ),
          _navTile(
            '위치기반 서비스 약관',
            null,
            () => _openPolicyUrl(_locationTermsUrl),
          ),
          _navTile(
            '오픈 소스 라이선스',
            null,
            () => showLicensePage(
              context: context,
              applicationName: 'TaxiMate',
              applicationVersion: '1.0.0',
            ),
          ),
          _navTile('버전 정보', '1.0.0', () {}),
          _sectionTitle('👤 계정'),
          _navTile(
            '탈퇴하기',
            null,
            () => _showWithdrawDialog(context),
            color: AppColors.red,
            icon: Icons.person_remove_outlined,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('약관 페이지를 열 수 없습니다.')),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('약관 페이지를 여는 중 오류가 발생했습니다.')),
      );
    }
  }


  Widget _sectionTitle(String t) => Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 8), child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.gray)));
  Widget _switchTile(String label, String sub, bool value, ValueChanged<bool> onChanged) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)), Text(sub, style: const TextStyle(fontSize: 11, color: AppColors.gray))])),
        Switch(value: value, activeColor: AppColors.primary, onChanged: onChanged),
      ]),
    ),
  );
  Widget _navTile(String label, String? value, VoidCallback onTap, {Color? color, IconData? icon}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Material(color: Colors.white, borderRadius: BorderRadius.circular(14), child: InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, color: color ?? AppColors.secondary, size: 20), const SizedBox(width: 14)],
          Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color ?? AppColors.secondary)),
          const Spacer(),
          if (value != null) Text(value, style: const TextStyle(fontSize: 12, color: AppColors.gray)),
          const Icon(Icons.chevron_right, color: AppColors.border, size: 20),
        ]),
      ),
    )),
  );

  void _showWithdrawDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          '탈퇴하기',
          style: TextStyle(color: AppColors.red),
        ),
        content: const Text(
          '정말 탈퇴하시겠습니까?\n탈퇴 후 계정 정보는 정책에 따라 1년간 보관됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);

              final result = await AuthService.withdraw(reason: '자진 탈퇴');

              if (!context.mounted) return;

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    result['message'] ?? '탈퇴 처리가 완료되었습니다.',
                  ),
                ),
              );

              if (result['success'] == true) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('탈퇴'),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 4. 고객지원 화면 (Support)
// ============================================================
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  static const String _supportEmail = 'crescit2026@gmail.com';

  Future<void> _copySupportEmail(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: _supportEmail));

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('이메일 주소가 복사되었습니다.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _appBar('고객지원'),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _supportCard(
              Icons.email_outlined,
              '이메일 문의',
              _supportEmail,
              const Color(0xFF4A6FFF),
              () => _copySupportEmail(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _supportCard(IconData icon, String title, String val, Color color, VoidCallback onTap) => Material(
    color: Colors.white, borderRadius: BorderRadius.circular(16),
    child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: Container(
      padding: const EdgeInsets.all(20), decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Row(children: [
        Container(width: 52, height: 52, decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color, size: 28)),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)), Text(val, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color))]),
        const Spacer(), const Icon(Icons.chevron_right, color: AppColors.border),
      ]),
    )),
  );
}

// ============================================================
// 5. 매너 로그 화면 (Manner)
// ============================================================
class _MannerScreen extends StatefulWidget {
  const _MannerScreen();
  @override
  State<_MannerScreen> createState() => _MannerScreenState();
}

class _MannerScreenState extends State<_MannerScreen> {
  static final DateFormat _logDateFormat = DateFormat('yyyy.MM.dd HH:mm');

  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  Future<void> _fetchLogs() async {
    try {
      final logs = await AuthService.getTrustScoreLogs();
      if (!mounted) return;
      setState(() {
        _logs = logs;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '매너 로그를 불러오는 데 실패했습니다.';
        _isLoading = false;
      });
    }
  }

  String _formatLogDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    try {
      return _logDateFormat.format(DateTime.parse(raw).toLocal());
    } catch (_) {
      return raw;
    }
  }

  String _getEventDisplayName(String eventType, String? reasonDetail) {
    final detail = reasonDetail?.trim() ?? '';

    if (eventType == 'EVALUATION' || detail.contains('동승 상호 평가')) {
      return '동승 상호 평가';
    }
    if (eventType == 'MANUAL_ADJUST' && detail.contains('정산 지연')) {
      return '정산 지연 패널티';
    }

    switch (eventType) {
      case 'TRIP_LEADER_SUCCESS':
        return '여정 개설 성공';
      case 'TRIP_PARTICIPATION_COMPLETE':
      case 'TRIP_PARTICIPATION_COMPLETED':
        return '동승 완료';
      case 'FAST_SETTLEMENT':
        return '빠른 정산';
      case 'STREAK_BONUS':
        return '연속 보너스';
      case 'NORMAL_CANCEL':
        return '일반 취소';
      case 'URGENT_CANCEL':
        return '긴급 취소';
      case 'NO_SHOW':
        return '노쇼';
      case 'MANUAL_ADJUST':
        if (detail != null && detail.contains('별점')) {
          return '동승 상호 평가';
        }
        return '수동 조정';
      default:
        return eventType;
    }
  }

  String _formatAppliedDelta(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return '-';
    final normalized = value.replaceAll('+', '').trim();
    if (normalized == '0.0' || normalized == '0') {
      return '변동 없음';
    }
    return value;
  }

  bool _isNeutralDelta(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return true;
    final normalized = value.replaceAll('+', '').trim();
    return normalized == '0.0' || normalized == '0';
  }

  Color _getDirectionColor(String direction) {
    switch (direction) {
      case 'GAIN':
        return AppColors.primary;
      case 'PENALTY':
        return AppColors.red;
      case 'ADJUST':
        return AppColors.accent;
      default:
        return AppColors.gray;
    }
  }

  IconData _getDirectionIcon(String direction) {
    switch (direction) {
      case 'GAIN':
        return Icons.arrow_upward;
      case 'PENALTY':
        return Icons.arrow_downward;
      case 'ADJUST':
        return Icons.sync;
      default:
        return Icons.remove;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _appBar('매너 로그'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.red)))
              : _logs.isEmpty
                  ? const Center(
                      child: Text(
                        '매너 로그가 없습니다.',
                        style: TextStyle(color: AppColors.gray),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _logs.length,
                      itemBuilder: (_, i) => _buildLogCard(_logs[i]),
                    ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    final direction = log['direction']?.toString() ?? '';
    final appliedDeltaRaw = log['applied_delta']?.toString();
    final isNeutral = _isNeutralDelta(appliedDeltaRaw);
    final color = isNeutral ? AppColors.gray : _getDirectionColor(direction);
    final icon = isNeutral ? Icons.remove : _getDirectionIcon(direction);
    final reasonDetail = log['reason_detail']?.toString().trim() ?? '';
    final eventLabel = _getEventDisplayName(
      log['event_type']?.toString() ?? '',
      reasonDetail.isEmpty ? null : reasonDetail,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        eventLabel,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.secondary,
                        ),
                      ),
                      Text(
                        _formatLogDate(log['created_at']?.toString()),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.gray,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    _formatAppliedDelta(appliedDeltaRaw),
                    style: TextStyle(
                      fontSize: isNeutral ? 12 : 13,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            if (reasonDetail.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reasonDetail,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.secondary,
                      ),
                    ),
                    if (log['score_after'] != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Text(
                            '변경 후 점수: ',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.gray,
                            ),
                          ),
                          Text(
                            '${log['score_after']}점',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.secondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 6. 신고하기 화면 (Report)
// ============================================================
class _ReportScreen extends StatefulWidget {
  const _ReportScreen();

  @override
  State<_ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<_ReportScreen> {
  List<_ReportTrip> _trips = [];
  bool _isLoading = true;
  String? _error;

  static const List<String> _reportReasons = [
    '노쇼',
    '정산 지연',
    '비매너 행위',
    '부적절한 채팅',
    '허위 정보 또는 허위 정산',
    '기타',
  ];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final list = await AuthService.getRecentCompanions();

      if (!mounted) return;

      setState(() {
        _trips = list.map((item) => _ReportTrip.fromJson(item)).toList();
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = '신고 가능한 여정을 불러오는 데 실패했습니다.';
        _isLoading = false;
      });
    }
  }

  bool _containsDangerousText(String text) {
    if (text.isEmpty) return false;

    final hasControlChars =
        RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(text);

    if (hasControlChars) return true;

    final dangerousPatterns = [
      RegExp(r'<\s*script', caseSensitive: false),
      RegExp(r'<\s*/\s*script', caseSensitive: false),
      RegExp(r'<\s*iframe', caseSensitive: false),
      RegExp(r'<\s*object', caseSensitive: false),
      RegExp(r'<\s*embed', caseSensitive: false),
      RegExp(r'<\s*link', caseSensitive: false),
      RegExp(r'<\s*meta', caseSensitive: false),
      RegExp(r'javascript\s*:', caseSensitive: false),
      RegExp(r'on\w+\s*=', caseSensitive: false),
      RegExp(r'data\s*:', caseSensitive: false),
    ];

    return dangerousPatterns.any((pattern) => pattern.hasMatch(text));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _appBar('신고하기'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetch,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    color: Colors.white,
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: AppColors.primary),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '최근 여정 및 동승자를 확인한 후 신고할 이용자를 선택해주세요.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.secondary,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 120, 20, 0),
                      child: Center(
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.red),
                        ),
                      ),
                    )
                  else if (_trips.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 120, 20, 0),
                      child: Center(
                        child: Text(
                          '신고 가능한 여정이 없습니다.',
                          style: TextStyle(color: AppColors.gray),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: _trips.map(_buildTripCard).toList(),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildTripCard(_ReportTrip trip) {
    final statusText = _tripStatusText(trip);
    final statusColor = _tripStatusColor(trip);

    return GestureDetector(
      onTap: () => _showCompanionSheet(trip),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.local_taxi_outlined,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trip.route,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.secondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${trip.rideDate} 출발',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.gray,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: statusColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '동승자 ${trip.companions.length}명',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.gray,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.border),
          ],
        ),
      ),
    );
  }

  String _tripStatusText(_ReportTrip trip) {
    if (trip.tripStatus == 'COMPLETED') return '정산 완료';
    if (trip.myParticipantStatus == 'LEFT') return '나간 여정';
    if (trip.tripStatus == 'OPEN') return '모집 중';
    if (trip.tripStatus == 'FULL') return '모집 완료';
    if (trip.tripStatus == 'CLOSED') return '마감';
    return trip.tripStatus;
  }

  Color _tripStatusColor(_ReportTrip trip) {
    if (trip.tripStatus == 'COMPLETED') return AppColors.primary;
    if (trip.myParticipantStatus == 'LEFT') return AppColors.red;
    return AppColors.accent;
  }

  void _showCompanionSheet(_ReportTrip trip) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    trip.route,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.secondary,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '신고할 동승자를 선택해주세요.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.gray,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ...trip.companions.map((companion) {
                  return _buildCompanionTile(trip, companion, context);
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompanionTile(
    _ReportTrip trip,
    _ReportCompanion companion,
    BuildContext companionSheetContext,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () async {
            Navigator.pop(companionSheetContext);

            await Future.delayed(const Duration(milliseconds: 180));

            if (!mounted) return;

            _showReasonSheet(trip, companion);
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.bg,
                  backgroundImage: companion.profileImage.isNotEmpty
                      ? NetworkImage(companion.profileImage)
                      : null,
                  child: companion.profileImage.isEmpty
                      ? const Icon(Icons.person, color: AppColors.gray)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        companion.nickname,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '@${companion.username}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.gray,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '신고',
                    style: TextStyle(
                      color: AppColors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showReportAlert(String message) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          '안내',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _showReasonSheet(_ReportTrip trip, _ReportCompanion companion) {
    final Set<String> selectedReasons = <String>{};
    final detailController = TextEditingController();
    final pageContext = context;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final isEtc = selectedReasons.contains('기타');

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 18),
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Text(
                        '${companion.nickname}님 신고',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        trip.route,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.gray,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        '신고 사유를 선택해주세요.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ..._reportReasons.map((reason) {
                        final selected = selectedReasons.contains(reason);

                        return GestureDetector(
                          onTap: () {
                            setSheetState(() {
                              if (selectedReasons.contains(reason)) {
                                selectedReasons.remove(reason);
                              } else {
                                selectedReasons.add(reason);
                              }
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.primaryLight
                                  : Colors.white,
                              border: Border.all(
                                color: selected
                                    ? AppColors.primary
                                    : AppColors.border,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                _roundCheck(selected),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    reason,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: selected
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      color: AppColors.secondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      if (isEtc) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: detailController,
                          maxLength: 500,
                          maxLines: 5,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(500),
                          ],
                          decoration: InputDecoration(
                            hintText: '기타 신고 사유를 500자 이내로 작성해주세요.',
                            filled: true,
                            fillColor: AppColors.bg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: AppColors.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: AppColors.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: AppColors.primary),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.red,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () async {
                            FocusManager.instance.primaryFocus?.unfocus();

                            if (selectedReasons.isEmpty) {
                              ScaffoldMessenger.of(pageContext).showSnackBar(
                                const SnackBar(content: Text('신고 사유를 선택해주세요.')),
                              );
                              return;
                            }

                            final detail = detailController.text.trim();

                            if (selectedReasons.contains('기타')) {
                              if (detail.isEmpty) {
                                await _showReportAlert('기타 신고 사유를 작성해주세요.');
                                return;
                              }

                              if (_containsDangerousText(detail)) {
                                await _showReportAlert('허용되지 않는 문자가 포함되어 있습니다.');
                                return;
                              }
                            }

                            final result = await AuthService.reportUser(
                              targetId: companion.id,
                              tripId: trip.id,
                              reason: selectedReasons.join(', '),
                              detail: selectedReasons.contains('기타') ? detail : '',
                            );

                            if (!mounted) return;

                            FocusManager.instance.primaryFocus?.unfocus();

                            Navigator.pop(sheetContext);

                            await Future.delayed(const Duration(milliseconds: 250));

                            if (!mounted) return;

                            ScaffoldMessenger.of(pageContext)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  content: Text(
                                    result['message'] ?? '신고가 접수되었습니다.',
                                  ),
                                ),
                              );

                            if (result['success'] == true) {
                              _fetch();
                            }
                          },
                          child: const Text(
                            '신고 제출',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() async {
      await Future.delayed(const Duration(milliseconds: 200));
      detailController.dispose();
    });
  }

  Widget _roundCheck(bool selected) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.primary : Colors.white,
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.border,
          width: 2,
        ),
      ),
      child: selected
          ? const Icon(Icons.check, color: Colors.white, size: 15)
          : null,
    );
  }
}

class _ReportTrip {
  final String id;
  final String rideDate;
  final String route;
  final String tripStatus;
  final String myParticipantStatus;
  final List<_ReportCompanion> companions;

  _ReportTrip({
    required this.id,
    required this.rideDate,
    required this.route,
    required this.tripStatus,
    required this.myParticipantStatus,
    required this.companions,
  });

  factory _ReportTrip.fromJson(Map<String, dynamic> json) {
    final rawCompanions = json['companions'];

    final companions = rawCompanions is List
        ? rawCompanions
            .whereType<Map>()
            .map((item) => _ReportCompanion.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList()
        : <_ReportCompanion>[];

    return _ReportTrip(
      id: '${json['trip_id'] ?? ''}',
      rideDate: '${json['ride_date'] ?? ''}',
      route: '${json['route'] ?? ''}',
      tripStatus: '${json['trip_status'] ?? ''}',
      myParticipantStatus: '${json['my_participant_status'] ?? ''}',
      companions: companions,
    );
  }
}

class _ReportCompanion {
  final String id;
  final String nickname;
  final String username;
  final String profileImage;

  _ReportCompanion({
    required this.id,
    required this.nickname,
    required this.username,
    required this.profileImage,
  });

  factory _ReportCompanion.fromJson(Map<String, dynamic> json) {
    return _ReportCompanion(
      id: '${json['id'] ?? ''}',
      nickname: '${json['nickname'] ?? '이름 없음'}',
      username: '${json['username'] ?? 'unknown'}',
      profileImage: '${json['profile_image'] ?? ''}',
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final String? sub;
  final Widget? screen;
  final Color? color;

  const _MenuItem({
    required this.icon,
    required this.label,
    this.sub,
    this.screen,
    this.color,
  });
}


// ============================================================
// 인증 관리 화면 (옥토모 단일 인증 체계)
// ============================================================
class _AuthScreen extends StatefulWidget {
  const _AuthScreen();

  @override
  State<_AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<_AuthScreen> {
  // 휴대폰 인증 여부만 관리합니다.
  bool _isPhoneVerified = false;

  // 휴대폰 인증 바텀시트 호출
  void _showPhoneAuthSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PhoneAuthBottomSheet(
        onVerified: (success) {
          if (success) {
            setState(() => _isPhoneVerified = true);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _appBar('인증 관리'),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _sectionTitle('본인 확인 인증'),
            _buildAuthTile(
              icon: Icons.phone_android_outlined,
              label: '휴대폰 번호 인증',
              isVerified: _isPhoneVerified,
              onTap: _isPhoneVerified ? () {} : _showPhoneAuthSheet,
            ),
            const SizedBox(height: 24),
            _buildInfoBox(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isPhoneVerified
                  ? AppColors.primary.withOpacity(0.1)
                  : AppColors.gray.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isPhoneVerified ? Icons.verified : Icons.shield_outlined,
              color: _isPhoneVerified ? AppColors.primary : AppColors.gray,
              size: 44
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _isPhoneVerified ? '인증이 완료되었습니다' : '전화번호가 바뀌었나요?',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.secondary),
          ),
          const SizedBox(height: 8),
          Text(
            _isPhoneVerified ? 'Crescit의 모든 기능을 안전하게 이용할 수 있습니다.' : '안전한 여정을 위해 새로운 휴대폰 번호를 인증해 주세요.',
            style: const TextStyle(fontSize: 13, color: AppColors.gray),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
    child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.gray)),
  );

  Widget _buildAuthTile({required IconData icon, required String label, required bool isVerified, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              border: Border.all(color: isVerified ? AppColors.primary.withOpacity(0.5) : AppColors.border),
              borderRadius: BorderRadius.circular(14)
            ),
            child: Row(
              children: [
                Icon(icon, color: isVerified ? AppColors.primary : AppColors.gray, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.secondary))
                ),
                if (isVerified)
                  const Row(
                    children: [
                      Text('인증됨', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                      SizedBox(width: 6),
                      Icon(Icons.check_circle, color: AppColors.primary, size: 20)
                    ],
                  )
                else
                  const Icon(Icons.chevron_right, color: AppColors.border),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoBox() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: AppColors.gray),
          SizedBox(width: 10),
          Expanded(child: Text('인증된 정보는 수정이 불가능하며, 탈퇴 시까지 안전하게 보관됩니다.', style: TextStyle(fontSize: 11, color: AppColors.gray, height: 1.5))),
        ],
      ),
    );
  }
}

// ============================================================
// 휴대폰 인증 바텀시트 (OCTOMO)
// ============================================================
class _PhoneAuthBottomSheet extends StatefulWidget {
  final Function(bool) onVerified;
  const _PhoneAuthBottomSheet({required this.onVerified});

  @override
  State<_PhoneAuthBottomSheet> createState() => _PhoneAuthBottomSheetState();
}

class _PhoneAuthBottomSheetState extends State<_PhoneAuthBottomSheet> {
  final _phoneCtrl = TextEditingController();
  bool _isLoading = false;
  bool _codeSent = false;
  bool _isVerifying = false;
  String _authCode = '';
  String _octomoNumber = '1666-3538';

  void _sendCode() async {
    if (_phoneCtrl.text.length < 10) return;
    setState(() => _isLoading = true);
    final result = await AuthService.sendVerificationCode(phone: _phoneCtrl.text.trim());
    setState(() {
      _isLoading = false;
      if (result['success']) {
        _codeSent = true;
        _authCode = result['code'] ?? '123456';
      }
    });
  }

  void _verify() async {
      setState(() => _isVerifying = true);


      final result = await AuthService.updateLoggedUserPhone(phone: _phoneCtrl.text.trim());

      setState(() => _isVerifying = false);
      if (result['success'] == true) { // 📍 verified가 아니라 success 체크 (갱신용 API 응답에 맞춰서)
        widget.onVerified(true);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('본인 인증 및 정보 갱신이 완료되었습니다.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] ?? '인증 실패')));
      }
    }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24, top: 24, left: 20, right: 20),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            const Text('휴대폰 번호 인증', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.secondary)),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone, decoration: InputDecoration(hintText: '010-0000-0000', filled: true, fillColor: AppColors.bg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _isLoading ? null : _sendCode,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                child: Text(_codeSent ? '재발송' : '코드받기', style: const TextStyle(fontWeight: FontWeight.bold)),
              )
            ]),
            if (_codeSent) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                child: Column(children: [
                  const Text('인증 코드를 문자로 보내주세요', style: TextStyle(fontSize: 13, color: AppColors.gray, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Text(_authCode, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: AppColors.primary, letterSpacing: 8)),
                  const SizedBox(height: 16),
                  SizedBox(width: double.infinity, height: 48, child: OutlinedButton.icon(
                    onPressed: () async => await launchUrl(Uri.parse('sms:$_octomoNumber?body=$_authCode')),
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('메시지 앱 바로 열기', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.primary, width: 1.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  )),
                ]),
              ),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, height: 52, child: ElevatedButton(
                onPressed: _isVerifying ? null : _verify,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                child: _isVerifying ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('인증 완료 확인', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              )),
            ],
          ],
        ),
      ),
    );
  }
}