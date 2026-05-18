import '../../service/auth_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../utils/colors.dart';
import '../location_search_screen.dart';
import 'home_tab.dart' as home;
import 'active_tab.dart';
import '../../service/trip_service.dart';
import 'message_tab.dart';
import 'dart:async';

class MatchingTab extends StatefulWidget {
  final VoidCallback? onGoHome;
  const MatchingTab({super.key, this.onGoHome});
  @override
  State<MatchingTab> createState() => _MatchingTabState();
}

class _MatchingTabState extends State<MatchingTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String? _selectedCardId;

  final TextEditingController _deptCtrl = TextEditingController();
  final TextEditingController _destCtrl = TextEditingController();
  final TextEditingController _kakaoCtrl = TextEditingController();

  int _maxPeople = 2;
  String? _selectedSeat;
  TimeOfDay? _selectedTime;

  bool _pinCreated = false;
  bool _isLoading = false;
  List<home.RidePin> _serverPins = [];
  bool _isFetching = false;

  double? _deptLat, _deptLng, _destLat, _destLng;
  static const _seats = ['조수석', '왼쪽 창가', '가운데', '오른쪽 창가'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (AuthSession.token != null && AuthSession.token!.isNotEmpty) {
        _fetchTrips();
      } else {
        print("로그인 전이라서 서버 통신(GPS 포함)을 차단함");
      }

      TripService.tripsRefreshNotifier.addListener(_onTripsChanged);
    }

  void _onTripsChanged() => _fetchTrips();

  @override
  void dispose() {
    TripService.tripsRefreshNotifier.removeListener(_onTripsChanged);
    _tabController.dispose();
    _searchCtrl.dispose();
    _deptCtrl.dispose();
    _destCtrl.dispose();
    _kakaoCtrl.dispose();
    super.dispose();
  }

  // 서버에서 핀 목록 가져오기
  Future<void> _fetchTrips() async {
    if (!mounted) return;
    setState(() => _isFetching = true);

    final List<dynamic> data = await TripService.getTrips(token: AuthSession.token ?? '');

    if (mounted) {
      setState(() {
        _serverPins = data.map((item) {
        final List<dynamic> rawSeats = item['taken_seats'] ?? [];
        final List<String> takenSeats = rawSeats.map((s) => s.toString()).toList();
        return home.RidePin(
          id: item['id'].toString(),
          hostId: item['host_nickname'] ?? '익명',
          dept: item['depart_name'],
          dest: item['arrive_name'],
          time: DateTime.parse(item['depart_time']).toLocal().toString().substring(11, 16),
          max: item['capacity'],
          cur: item['current_count'],
          lat: double.parse(item['depart_lat'].toString()),
          lng: double.parse(item['depart_lng'].toString()),
          isMine: item['is_mine'] == true,
          takenSeats: takenSeats,
        );}).toList();
        _isFetching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          Expanded(child: TabBarView(controller: _tabController, children: [_buildSearchTab(), _buildCreateTab()])),
        ]),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 10),
          child: Text('매칭', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.secondary)),
        ),
        TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.gray,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: const UnderlineTabIndicator(borderSide: BorderSide(color: AppColors.primary, width: 2.5)),
          tabs: const [Tab(text: '🔍 검색'), Tab(text: '📍 핀 생성')],
        ),
      ]),
    );
  }

  Widget _buildSearchTab() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: GestureDetector(
          onTap: () async {
            final result = await Navigator.push<Map<String, dynamic>>(context, MaterialPageRoute(builder: (_) => const LocationSearchScreen(title: '장소')));
            if (result != null) setState(() => _searchQuery = result['name'] as String);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              const Icon(Icons.search, color: AppColors.gray, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(_searchQuery.isEmpty ? '출발지 또는 목적지 검색...' : _searchQuery, style: TextStyle(fontSize: 14, color: _searchQuery.isEmpty ? AppColors.gray : AppColors.secondary))),
              if (_searchQuery.isNotEmpty) GestureDetector(onTap: () => setState(() => _searchQuery = ''), child: const Icon(Icons.clear, color: AppColors.gray, size: 18)),
            ]),
          ),
        ),
      ),
      Expanded(child: _buildPinList()),
    ]);
  }

  Widget _buildPinList() {
    final pins = _serverPins.where((pin) {
        final matchesSearch = _searchQuery.isEmpty ||
                             pin.dept.contains(_searchQuery) ||
                             pin.dest.contains(_searchQuery);

        return matchesSearch && !pin.isMine;
      }).toList();

      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Text(
            _searchQuery.isEmpty ? '전체 ${pins.length}건' : '"$_searchQuery" ${pins.length}건',
            style: const TextStyle(fontSize: 12, color: AppColors.gray)
          )
        ),

      Expanded(
        child: _isFetching && _serverPins.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _fetchTrips,
                color: AppColors.primary,
                child: pins.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 100),
                          Center(child: Text('표시할 동승 핀이 없습니다.', style: TextStyle(color: AppColors.gray))),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: pins.length,
                        itemBuilder: (_, i) => _buildSearchCard(pins[i]),
                      ),
              ),
      ),
    ]);
  }

  Widget _buildSearchCard(home.RidePin pin) {
    final isFull = pin.cur >= pin.max;
    final isMine = pin.isMine;
    final isSelected = _selectedCardId == pin.id;

    return ListenableBuilder(
      listenable: globalActiveRideState,
      builder: (context, _) {
        final int tripId = int.tryParse(pin.id) ?? 0;
        final isAlreadyJoined =
            globalActiveRideState.waitingPins.any((p) => p.id == tripId) ||
            globalActiveRideState.myPins.any((p) => p.id == tripId);

        return GestureDetector(
      onTap: () => setState(() => _selectedCardId = isSelected ? null : pin.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryLight : Colors.white,
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.border, width: isSelected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: [
          Row(children: [
            Container(width: 44, height: 44, decoration: const BoxDecoration(color: AppColors.bg, shape: BoxShape.circle), child: const Icon(Icons.person, color: AppColors.gray, size: 26)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('@${pin.hostId}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.secondary)),
              const SizedBox(height: 6),
              Row(children: [
                Flexible(child: Text(pin.dept, style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('→', style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.w700))),
                Flexible(child: Text(pin.dest, style: const TextStyle(fontSize: 12, color: AppColors.secondary), overflow: TextOverflow.ellipsis)),
              ]),
            ])),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)), child: Column(children: [const Text('출발', style: TextStyle(fontSize: 9, color: Colors.white70)), Text(pin.time, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white))])),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            ...List.generate(pin.max, (j) => Container(width: 22, height: 22, margin: const EdgeInsets.only(right: 4), decoration: BoxDecoration(color: j < pin.cur ? AppColors.primary : AppColors.bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: j < pin.cur ? AppColors.primary : AppColors.border)), child: j < pin.cur ? const Icon(Icons.person, color: Colors.white, size: 13) : null)),
            const SizedBox(width: 6),
            Text('${pin.cur}/${pin.max}명', style: const TextStyle(fontSize: 11, color: AppColors.gray)),
          ]),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            child: isSelected ? Column(children: [
              const SizedBox(height: 12),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: isMine || isFull || isAlreadyJoined ? AppColors.gray : AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: isMine || isFull || isAlreadyJoined ? null : () async {
                      if (globalActiveRideState.activePinCount >= 2) {
                        _showSnackBar(
                          '동시에 최대 2개의 동승에만 참여할 수 있습니다.',
                          AppColors.red,
                        );
                        return;
                      }
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RideJoinScreen(
                            pin: {
                              'id': pin.id,
                              'hostId': pin.hostId,
                              'dept': pin.dept,
                              'dest': pin.dest,
                              'time': pin.time,
                              'max': pin.max,
                              'cur': pin.cur,
                              'takenSeats': pin.takenSeats,
                            },
                          ),
                        ),
                      );
                      if (mounted) {
                        _fetchTrips();
                      }
                    },
                    child: Text(
                      isMine ? '내가 생성한 모집글입니다' : isAlreadyJoined ? '이미 참여한 핀입니다' : isFull ? '마감' : '참여하기',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ),
            ]) : const SizedBox.shrink(),
          ),
        ]),
      ),
    );
      },
    );
  }

  // ============================================================
  // 핀 생성 탭
  // ============================================================
  Widget _buildCreateTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_pinCreated)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                border: Border.all(color: AppColors.primary),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Text('✅', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 10),
                  Text('핀이 생성되었습니다!',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                ],
              ),
            ),

          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.bg,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.person, color: AppColors.gray, size: 26),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('@${AuthSession.username ?? 'user'}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Row(children: [
                      _tag('인증됨 ✓'),
                      const SizedBox(width: 4),
                      _tag('⭐ 4.8', color: AppColors.accent, bg: const Color(0xFFFFF8E6)),
                    ]),
                  ],
                ),
              ],
            ),
          ),

          _label('📍 출발지'), const SizedBox(height: 6),
          _locationTextField(
            controller: _deptCtrl,
            hint: '출발지 검색하기',
            isDeparture: true,
            onTap: () => _openLocationSearch(true),
          ),
          const SizedBox(height: 14),

          _label('🏁 목적지'), const SizedBox(height: 6),
          _locationTextField(
            controller: _destCtrl,
            hint: '목적지 검색하기',
            isDeparture: false,
            onTap: () => _openLocationSearch(false),
          ),
          const SizedBox(height: 14),

          _label('🕐 출발 시간'), const SizedBox(height: 6),
          GestureDetector(
            onTap: _showTimePicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.bg,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time, color: AppColors.gray, size: 20),
                  const SizedBox(width: 10),
                  Text((_selectedTime ?? TimeOfDay.now()).format(context),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.secondary)),
                  const Spacer(),
                  const Icon(Icons.chevron_right, color: AppColors.gray),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          _label('👥 모집 인원 (최대 4명, 본인 포함 기준)'), const SizedBox(height: 8),
          Row(
            children: [2, 3, 4].map((n) => Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _maxPeople = n),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: _maxPeople == n ? AppColors.primary : AppColors.bg,
                      border: Border.all(color: _maxPeople == n ? AppColors.primary : AppColors.border, width: 1.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$n명', textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14,
                            color: _maxPeople == n ? Colors.white : AppColors.gray)),
                  ),
                ),
              ),
            )).toList(),
          ),
          const SizedBox(height: 16),

          _label('💺 좌석 선택'), const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: _seats.map((seat) => Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedSeat = seat),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 45,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: _selectedSeat == seat ? AppColors.primaryLight : AppColors.bg,
                    border: Border.all(
                      color: _selectedSeat == seat ? AppColors.primary : AppColors.border,
                      width: _selectedSeat == seat ? 1.5 : 1,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.event_seat, size: 15,
                          color: _selectedSeat == seat ? AppColors.primary : AppColors.gray),
                      const SizedBox(width: 5),
                      Text(seat,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _selectedSeat == seat ? AppColors.primary : AppColors.gray,
                          )),
                    ],
                  ),
                ),
              ),
            )).toList(),
          ),
          const SizedBox(height: 16),

          _label('💛 카카오페이 링크 (필수)'), const SizedBox(height: 6),
          TextField(
            controller: _kakaoCtrl,
            decoration: InputDecoration(
              hintText: 'https://qr.kakaopay.com/...',
              hintStyle: const TextStyle(fontSize: 12, color: AppColors.gray),
              filled: true, fillColor: const Color(0xFFFFFDE7),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.accent)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.accent)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: _isLoading ? null : _handleCreate,
              child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text('📍 핀 생성하기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showTimePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        TimeOfDay tempTime = _selectedTime ?? TimeOfDay.now();
        return StatefulBuilder(
          builder: (ctx, setModalState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
              const Text('출발 시간 선택', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: false,
                  initialDateTime: DateTime(2024, 1, 1, (_selectedTime ?? TimeOfDay.now()).hour, (_selectedTime ?? TimeOfDay.now()).minute),
                  onDateTimeChanged: (dt) {
                    setModalState(() => tempTime = TimeOfDay(hour: dt.hour, minute: dt.minute));
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                    onPressed: () { setState(() => _selectedTime = tempTime); Navigator.pop(context); },
                    child: const Text('확인', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleCreate() async {
    if (globalActiveRideState.activePinCount >= 2) {
      _showSnackBar('동시에 최대 2개의 동승에만 참여할 수 있습니다.', AppColors.red);
      return;
    }
    if (_deptCtrl.text.isEmpty || _destCtrl.text.isEmpty) {
      _showSnackBar('출발지와 목적지를 입력해주세요.', AppColors.red);
      return;
    }
    if (_deptLat == null || _destLat == null) {
      _showSnackBar('검색을 통해 장소를 선택해주세요.', AppColors.red);
      return;
    }
    if (_selectedSeat == null) {
      _showSnackBar('본인의 좌석을 선택해주세요.', AppColors.red);
      return;
    }
    final kakaoLink = _kakaoCtrl.text.trim();
    final kakaoPayLinkPattern = RegExp(r'^https?://qr\.kakaopay\.com/');
    if (kakaoLink.isEmpty || !kakaoPayLinkPattern.hasMatch(kakaoLink)) {
      _showSnackBar(
        '유효한 카카오페이 링크를 입력해주세요. (http(s)://qr.kakaopay.com/ 로 시작)',
        AppColors.red,
      );
      return;
    }

    setState(() => _isLoading = true);

    final now = DateTime.now();
    final effectiveTime = _selectedTime ?? TimeOfDay.now();
    final departDateTime = DateTime(
      now.year, now.month, now.day,
      effectiveTime.hour, effectiveTime.minute,
    );

    final result = await TripService.createTrip(
      token: AuthSession.token ?? '',
      deptName: _deptCtrl.text,
      deptLat: _deptLat!,
      deptLng: _deptLng!,
      destName: _destCtrl.text,
      destLat: _destLat!,
      destLng: _destLng!,
      departTime: departDateTime,
      capacity: _maxPeople,
      seatPosition: _selectedSeat!,
      kakaoLink: kakaoLink,
    );

    if (!mounted) return;

    if (result['success']) {
      final int newTripId = result['id'];
      await _fetchTrips();
      TripService.tripsRefreshNotifier.notifyListeners();
      TripService.chatRoomsRefreshNotifier.notifyListeners();

      final chatResult = await TripService.createChatRoom(
        token: AuthSession.token ?? '',
        tripId: newTripId,
      );

      if (chatResult['success']) {
        print("✅ 채팅방 생성 성공: ID ${chatResult['id']}");
      } else {
        print("❌ 채팅방 생성 실패: ${chatResult['message']}");
      }
      await _fetchTrips();
      TripService.tripsRefreshNotifier.notifyListeners();

      setState(() => _pinCreated = true);

      _deptCtrl.clear(); _destCtrl.clear(); _kakaoCtrl.clear();
      _deptLat = null; _destLat = null;

      widget.onGoHome?.call();

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _pinCreated = false);
      });
    } else {
      _showSnackBar(result['message'], AppColors.red);
    }

    setState(() => _isLoading = false);
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: color,
    ));
  }

  Widget _label(String text) =>
      Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.secondary));

  Future<void> _openLocationSearch(bool isDeparture) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationSearchScreen(
          title: isDeparture ? '출발지' : '목적지',
        ),
      ),
    );

    if (result != null) {
      setState(() {
        if (isDeparture) {
          _deptCtrl.text = result['name'] as String;
          _deptLat = result['lat'] as double;
          _deptLng = result['lng'] as double;
        } else {
          _destCtrl.text = result['name'] as String;
          _destLat = result['lat'] as double;
          _destLng = result['lng'] as double;
        }
      });
    }
  }

  Widget _locationTextField({
    required TextEditingController controller,
    required String hint,
    required bool isDeparture,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              isDeparture ? Icons.location_on : Icons.location_on_outlined,
              color: controller.text.isNotEmpty ? AppColors.primary : AppColors.gray,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                controller.text.isNotEmpty ? controller.text : hint,
                style: TextStyle(
                  fontSize: 14,
                  color: controller.text.isNotEmpty ? AppColors.secondary : AppColors.gray,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.gray, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _tag(String text, {Color color = AppColors.primary, Color bg = AppColors.primaryLight}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
        child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
      );
}

// ============================================================
// 동승 참여 화면 - 참여 버튼 클릭 시 실행
// ============================================================
class RideJoinScreen extends StatefulWidget {
  final Map<String, dynamic> pin;
  const RideJoinScreen({super.key, required this.pin});

  @override
  State<RideJoinScreen> createState() => _RideJoinScreenState();
}

class _RideJoinScreenState extends State<RideJoinScreen> {
  String? _selectedSeat;
  late List<String> _takenSeats; // 빈 배열로 수정 완료!
  bool _isLoading = false;
  @override
    void initState() {
      super.initState();
      // 부모 위젯(MatchingTab)에서 넘겨준 'takenSeats' 리스트를 가져옵니다.
      _takenSeats = List<String>.from(widget.pin['takenSeats'] ?? []);
    }

    // 여기에 이어서 아래의 매핑 함수를 추가하세요.
    String _mapKoToEn(String ko) {
      switch (ko) {
        case '조수석': return 'FRONT_PASSENGER';
        case '왼쪽 창가': return 'REAR_LEFT';
        case '가운데': return 'REAR_MIDDLE';
        case '오른쪽 창가': return 'REAR_RIGHT';
        default: return '';
      }
    }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: globalActiveRideState,
      builder: (context, _) {
        final pin = widget.pin;
        final int cur = pin['cur'] as int;
        final int max = pin['max'] as int;
        final bool isFull = cur >= max;

        final rawTripId = pin['id'];
        final int tripId = rawTripId is int
            ? rawTripId
            : int.parse(rawTripId.toString());
        final isAlreadyJoined = globalActiveRideState.waitingPins.any((p) => p.id == tripId) ||
            globalActiveRideState.myPins.any((p) => p.id == tripId);

    return Scaffold(
      backgroundColor: Colors.white,

      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.secondary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('동승 참여',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.secondary)),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('👤 대표자'),
            const SizedBox(height: 10),
            _card(child: Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.bg, shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.person, color: AppColors.gray, size: 28),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('@${pin['hostId']}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.secondary)),
                    const SizedBox(height: 4),
                    Row(children: [
                      _tag('인증됨 ✓'),
                      const SizedBox(width: 4),
                      _tag('⭐ 4.8', color: AppColors.accent, bg: const Color(0xFFFFF8E6)),
                    ]),
                  ],
                ),
              ],
            )),
            const SizedBox(height: 20),

            _sectionTitle('🗺️ 경로'),
            const SizedBox(height: 10),
            _card(child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: _routeRow(Icons.my_location, AppColors.primary, '출발지', '${pin['dept']}'),
                  ),
                ),
                Column(children: List.generate(3, (_) =>
                    Container(width: 2, height: 6, margin: const EdgeInsets.symmetric(vertical: 2), color: AppColors.border))),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: _routeRow(Icons.location_on, AppColors.red, '목적지', '${pin['dest']}'),
                  ),
                ),
              ],
            )),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('🕐 출발 시간'),
                    const SizedBox(height: 10),
                    _card(child: Row(children: [
                      const Icon(Icons.access_time_rounded, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text('${pin['time']}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.secondary)),
                    ])),
                  ],
                )),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('👥 모집 인원'),
                    const SizedBox(height: 10),
                    _card(child: Row(children: [
                      ...List.generate(max, (j) => Container(
                        width: 20, height: 20, margin: const EdgeInsets.only(right: 3),
                        decoration: BoxDecoration(
                          color: j < cur ? AppColors.primary : AppColors.bg,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: j < cur ? AppColors.primary : AppColors.border),
                        ),
                        child: j < cur ? const Icon(Icons.person, color: Colors.white, size: 12) : null,
                      )),
                      const SizedBox(width: 6),
                      Text('$cur/$max', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.secondary)),
                    ])),
                  ],
                )),
              ],
            ),
            const SizedBox(height: 20),

            _sectionTitle('💺 좌석 선택'),
            const SizedBox(height: 4),
            const Text('빈 좌석을 선택해 주세요.', style: TextStyle(fontSize: 11, color: AppColors.gray)),
            const SizedBox(height: 10),
            _card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F5F5),
                              border: Border.all(color: AppColors.gray.withOpacity(0.2)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Column(
                              children: [
                                Icon(Icons.settings, size: 18, color: AppColors.gray),
                                SizedBox(height: 4),
                                Text('운전석', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.gray)),
                                Text('운전자', style: TextStyle(fontSize: 9, color: AppColors.gray)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: _seatButton('조수석', Icons.airline_seat_recline_extra)),
                      ],
                    ),

                    const SizedBox(height: 8),
                    const Divider(color: AppColors.border, height: 1),
                    const SizedBox(height: 8),

                    Row(
                      children: [
                        Expanded(child: _seatButton('왼쪽 창가', Icons.airline_seat_recline_normal)),
                        const SizedBox(width: 8),
                        Expanded(child: _seatButton('가운데', Icons.airline_seat_legroom_normal)),
                        const SizedBox(width: 8),
                        Expanded(child: _seatButton('오른쪽 창가', Icons.airline_seat_recline_normal)),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _legend(AppColors.primaryLight, AppColors.primary, '선택됨'),
                        const SizedBox(width: 12),
                        _legend(AppColors.bg, AppColors.border, '비어있음'),
                        const SizedBox(width: 12),
                        _legend(const Color(0xFFF5F5F5), AppColors.gray, '사용 중'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: (isFull || _selectedSeat == null || isAlreadyJoined)
                      ? AppColors.gray
                      : AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                onPressed: (isFull || _selectedSeat == null || _isLoading || isAlreadyJoined)
                    ? null
                    : _handleJoin,
                child: _isLoading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(
                      isAlreadyJoined
                          ? '이미 참여한 핀입니다'
                          : isFull
                              ? '마감된 팀입니다'
                              : _selectedSeat == null
                                  ? '좌석을 선택해 주세요'
                                  : '참여하기',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
      },
    );
  }

  Widget _seatButton(String label, IconData icon) {
    final isTaken = _takenSeats.contains(_mapKoToEn(label));
    final isSelected = _selectedSeat == label;
    final Color bg = isTaken ? const Color(0xFFF5F5F5) : isSelected ? AppColors.primaryLight : AppColors.bg;
    final Color border = isTaken ? AppColors.gray : isSelected ? AppColors.primary : AppColors.border;
    final Color textColor = isTaken ? AppColors.gray : isSelected ? AppColors.primary : AppColors.secondary;

    return GestureDetector(
      onTap: isTaken ? null : () => setState(() => _selectedSeat = isSelected ? null : label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border, width: isSelected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Icon(icon, size: 22, color: isTaken ? AppColors.gray : isSelected ? AppColors.primary : AppColors.secondary),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(isTaken ? '사용 중' : '비어있음', style: TextStyle(fontSize: 10, color: isTaken ? AppColors.gray : AppColors.primary)),
        ]),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white, border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );

  Widget _routeRow(IconData icon, Color color, String label, String value) => Row(children: [
    Icon(icon, color: color, size: 22),
    const SizedBox(width: 12),
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 10, color: AppColors.gray)),
      Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.secondary)),
    ]),
  ]);

  Widget _sectionTitle(String text) =>
      Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.secondary));

  Widget _tag(String text, {Color color = AppColors.primary, Color bg = AppColors.primaryLight}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
        child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
      );

  Widget _legend(Color bg, Color border, String label) => Row(children: [
    Container(width: 14, height: 14,
        decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(4))),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 10, color: AppColors.gray)),
  ]);

  Future<void> _handleJoin() async {
    if (globalActiveRideState.activePinCount >= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('동시에 최대 2개의 동승에만 참여할 수 있습니다.'),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final rawTripId = widget.pin['id'];
    final int tripId = rawTripId is int
        ? rawTripId
        : int.parse(rawTripId.toString());

    final result = await TripService.joinTrip(
      token: AuthSession.token ?? '',
      tripId: tripId,
      seatPosition: _selectedSeat!,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success']) {
       final chatResult = await TripService.createChatRoom(
        token: AuthSession.token ?? '',
        tripId: tripId,
      );

      TripService.tripsRefreshNotifier.notifyListeners();
      TripService.chatRoomsRefreshNotifier.notifyListeners();

      final int chatRoomId = chatResult['success']
          ? int.tryParse(chatResult['id'].toString()) ?? tripId
          : tripId;

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('참여 완료! 🎉',
              style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.secondary)),
          content: Text('@${widget.pin['hostId']} 팀에 참여했습니다.\n좌석: $_selectedSeat',
              style: const TextStyle(fontSize: 13, color: AppColors.gray)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) {
                      final tripId = widget.pin['id'] is int
                        ? widget.pin['id'] as int
                        : int.parse(widget.pin['id'].toString());
                      return ChatRoomScreen(
                        room: ChatRoomModel(
                          id: chatRoomId,
                          tripId: tripId,
                          name: '${widget.pin['dept']} -> ${widget.pin['dest']}',
                          lastMessage: '채팅방이 생성되었습니다.',
                          time: widget.pin['time']?.toString() ?? '',
                          unreadCount: 0,
                          pinnedNotice: '택시 번호 및 만날 위치를 꼭 공유해주세요!',
                          isLeader: false,
                        ),
                        myNickname: AuthSession.username ?? '나',
                      );
                    },
                  ),
                );
               },
              child: const Text('확인', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['message'] ?? '참여에 실패했습니다.'),
        backgroundColor: AppColors.red,
      ));
    }
  }
}