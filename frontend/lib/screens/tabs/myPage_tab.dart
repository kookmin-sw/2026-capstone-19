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
  const MyPageTab({super.key});
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
    final int count = userData['successful_streak_count'] ?? 0;

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
    final int tripCount = userData['successful_streak_count'] ?? 0;

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
      setState(() { _histories = history; _isLoading = false; });
    } catch (e) {
      setState(() { _error = '이용 내역을 불러오는데 실패했습니다: $e'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthSession.isLoggedIn) return Scaffold(appBar: _appBar('이용 내역'), body: const Center(child: Text('로그인이 필요합니다.')));
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _appBar('이용 내역'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.red)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _histories.length,
              itemBuilder: (_, i) => _buildHistoryCard(_histories[i]),
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
  bool _chatAlarm = true;
  bool _nightAlarm = false;
  bool _chatEnterAlarm = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _appBar('설정'),
      body: ListView(
        children: [
          _sectionTitle('🔔 알림 설정'),
          _switchTile('푸시 알림 동의', '앱 전체 알림 수신', _pushAlarm, (v) => setState(() => _pushAlarm = v)),
          _switchTile('채팅 알림', '채팅방 메시지 알림', _chatAlarm, (v) => setState(() => _chatAlarm = v)),
          _switchTile('야간 알림 (22시~8시)', '야간 시간대 알림 차단', _nightAlarm, (v) => setState(() => _nightAlarm = v)),
          _sectionTitle('💬 채팅 설정'),
          _switchTile('채팅방 입장 알림', '누군가 입장 시 알림', _chatEnterAlarm, (v) => setState(() => _chatEnterAlarm = v)),
          _navTile('채팅 글꼴 크기', '기본', () {}),
          _sectionTitle('📋 약관 및 정책'),
          _navTile('개인정보 처리방침', null, () {}),
          _navTile('서비스 이용약관', null, () {}),
          _sectionTitle('⚠️ 계정'),
          _navTile('탈퇴하기', null, () => _showWithdrawDialog(context), color: AppColors.red, icon: Icons.person_remove_outlined),
          const SizedBox(height: 32),
        ],
      ),
    );
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
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('탈퇴하기', style: TextStyle(color: AppColors.red)),
      content: const Text('정말 탈퇴하시겠습니까?'),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.red), onPressed: () {}, child: const Text('탈퇴'))],
    ));
  }
}

// ============================================================
// 4. 고객지원 화면 (Support)
// ============================================================
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _appBar('고객지원'),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          _supportCard(Icons.phone, '전화 문의', '010-5410-1536', AppColors.primary, () async => await launchUrl(Uri.parse('tel:15880000'))),
          const SizedBox(height: 12),
          _supportCard(Icons.email_outlined, '이메일 문의', '2020gomtang@gmail.com', const Color(0xFF4A6FFF), () async => await launchUrl(Uri.parse('mailto:support@taximate.app'))),
        ]),
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
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  Future<void> _fetchLogs() async {
    final logs = await AuthService.getTrustScoreLogs();
    setState(() { _logs = logs; _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _appBar('매너 로그'),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _logs.length,
        itemBuilder: (_, i) => _buildLogCard(_logs[i]),
      ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    final isGain = log['direction'] == 'GAIN';
    final color = isGain ? AppColors.primary : AppColors.red;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(isGain ? Icons.arrow_upward : Icons.arrow_downward, color: color, size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(log['event_type'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)), Text(log['created_at'], style: const TextStyle(fontSize: 11, color: AppColors.gray))])),
        Text(log['applied_delta'], style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
      ]),
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
  List<_RecentPassenger> _passengers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final list = await AuthService.getRecentCompanions();
    setState(() {
      _passengers = list.map((c) => _RecentPassenger(id: c['id'].toString(), nickname: c['nickname'], rideDate: c['ride_date'], route: c['route'])).toList();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _appBar('신고하기'),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : Column(children: [
        Container(padding: const EdgeInsets.all(20), color: AppColors.bg, child: const Row(children: [Icon(Icons.info_outline, color: AppColors.primary), SizedBox(width: 12), Expanded(child: Text('최근 동승자 중 신고할 이용자를 선택해주세요.'))])),
        Expanded(child: ListView.builder(padding: const EdgeInsets.all(16), itemCount: _passengers.length, itemBuilder: (_, i) => _buildPassengerCard(_passengers[i]))),
      ]),
    );
  }

  Widget _buildPassengerCard(_RecentPassenger p) => GestureDetector(
    onTap: () {}, // 바텀시트 로직 등 연결 가능
    child: Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        const CircleAvatar(backgroundColor: AppColors.bg, child: Icon(Icons.person, color: AppColors.gray)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(p.nickname, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)), Text(p.route, style: const TextStyle(fontSize: 12, color: AppColors.primary))])),
        Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: AppColors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Text('신고', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.bold))),
      ]),
    ),
  );
}

// 보조 클래스 및 미구현 화면
class _MenuItem {
  final IconData icon; final String label; final String? sub; final Widget? screen; final Color? color;
  const _MenuItem({required this.icon, required this.label, this.sub, this.screen, this.color});
}
class _RecentPassenger {
  final String id, nickname, rideDate, route;
  _RecentPassenger({required this.id, required this.nickname, required this.rideDate, required this.route});
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
            _isPhoneVerified ? '인증이 완료되었습니다' : '본인 인증이 필요합니다',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.secondary),
          ),
          const SizedBox(height: 8),
          Text(
            _isPhoneVerified ? 'Crescit의 모든 기능을 안전하게 이용할 수 있습니다.' : '안전한 거래를 위해 휴대폰 인증을 진행해 주세요.',
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