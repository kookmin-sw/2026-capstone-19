// ============================================================
// 📁 lib/screens/tabs/home_tab.dart
//
// [필수 패키지 설치] pubspec.yaml에 추가 후 flutter pub get
//   kakao_map_plugin: ^0.3.2
//   geolocator: ^13.0.0
//   permission_handler: ^11.0.0
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';
import 'package:geolocator/geolocator.dart';
import '../../utils/colors.dart';
import 'matching_tab.dart';
import 'active_tab.dart';
import '../location_search_screen.dart';
import '../../service/trip_service.dart';
import '../../service/auth_session.dart';

// 탭 전환 신호 역할 (인덱스 전달)
typedef OnTabChange = void Function(int index);

// 핀 데이터 모델
class RidePin {
  final String id, hostId, dept, dest, time;  // 핀 ID, 대표자 ID, 출발지, 목적지, 출발 시각
  final int max, cur; // 최대 모집 인원, 현재 참여 인원
  final double lat, lng; // 실제 좌표
  final bool isMine;
  final List<String> takenSeats;

  const RidePin({
    required this.id, required this.hostId,
    required this.dept, required this.dest, required this.time,
    required this.max, required this.cur,
    required this.lat, required this.lng,
    this.isMine = false,
    this.takenSeats = const [],
  });

  bool get isFull => cur >= max; // 최대 인원 모집 완료 시 마감 상태로 전환

  // 현재 지도 중심과의 거리 계산 (카메라 이동 시 필터링용)
  double distanceTo(double centerLat, double centerLng) {
    return Geolocator.distanceBetween(lat, lng, centerLat, centerLng);
  }
}

// ============================================================
List<RidePin> globalPins = [];
// 홈 탭 상태 변화 관리 클래스 (탭 전환 시)
class HomeTab extends StatefulWidget {
  final OnTabChange? onTabChange;
  final VoidCallback? onGoToCreate; // +버튼 용 콜백
  const HomeTab({super.key, this.onTabChange, this.onGoToCreate});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  // 지도 컨트롤러
  bool _canLoadMap = false;
  KakaoMapController? _mapController;

  // 상태
  Position? _currentPosition;       // 현재 GPS 위치
  StreamSubscription<Position>? _positionStream; // 실시간 위치 스트림
  bool _locationLoading = true;      // GPS 로딩 중
  String? _activePinId;              // 클릭된 핀 ID
  String? _selectedRideId;           // 목록에서 선택된 카드 ID
  bool _showNotifications = false;
  List<RidePin> _visiblePins = [];   // 현재 지도 영역의 핀 목록
  double _mapCenterLat = 37.6108;    // 지도 중심 위도 (기본: 국민대학교)
  double _mapCenterLng = 126.9971;   // 지도 중심 경도
  bool _isMapReady = false;          // 지도 준비 완료 여부
  bool _showActiveDetail = false;    // 이용 중 창

  final _activeRideState = globalActiveRideState;

  final DraggableScrollableController _sheetController = DraggableScrollableController();

  static const _dummyNotifications = [];

  int _lastPinCount = globalPins.length;

  void _onTripsChanged() {
    _fetchServerPins(moveToNewest: true);
  }

  Future<void> _fetchServerPins({bool moveToNewest = false}) async {
    final token = AuthSession.token ?? '';
    if (token.isEmpty) return;

    final trips = await TripService.getTrips(token: token);

    final serverPins = trips.map<RidePin>((trip) {
      final departTimeText = (trip['depart_time'] ?? '').toString();
      final parsedTime = DateTime.tryParse(departTimeText)?.toLocal();

      final timeText = parsedTime == null
          ? ''
          : '${parsedTime.hour.toString().padLeft(2, '0')}:${parsedTime.minute.toString().padLeft(2, '0')}';

      final participants = trip['participants'];
      String hostId = 'leader';

      if (participants is List && participants.isNotEmpty) {
        final leader = participants.firstWhere(
          (p) => p['role'] == 'LEADER',
          orElse: () => participants.first,
        );

        hostId = (leader['nickname'] ?? 'user_${leader['user']}').toString();
      }

      return RidePin(
        id: trip['id'].toString(),
        hostId: (trip['host_nickname'] ?? hostId).toString(),
        dept: (trip['depart_name'] ?? '').toString(),
        dest: (trip['arrive_name'] ?? '').toString(),
        time: timeText,
        max: trip['capacity'] ?? 0,
        cur: trip['current_count'] ?? 0,
        lat: double.tryParse(trip['depart_lat'].toString()) ?? 0.0,
        lng: double.tryParse(trip['depart_lng'].toString()) ?? 0.0,
        isMine: trip['is_mine'] == true || (trip['host_nickname'] ?? hostId).toString() == (AuthSession.username ?? ''),
        takenSeats: (trip['taken_seats'] as List? ?? []).map((s) => s.toString()).toList(),
      );
    }).toList();

    if (!mounted) return;

    globalPins = serverPins;
    _lastPinCount = globalPins.length;

    if (moveToNewest && globalPins.isNotEmpty && _mapController != null) {
      final newestPin = globalPins.first;
      _mapCenterLat = newestPin.lat;
      _mapCenterLng = newestPin.lng;
      _mapController!.setCenter(LatLng(newestPin.lat, newestPin.lng));
      _mapController!.setLevel(4);
    }

    _updateVisiblePins(_mapCenterLat, _mapCenterLng);

    if (_isMapReady) {
      await _refreshMapMarkers();
    }
  }

  // 생명주기 관리
  @override
  void initState() {
    super.initState();
    TripService.tripsRefreshNotifier.addListener(_onTripsChanged);

      // 🔴 2. 무거운 작업들은 순서대로 실행 (시퀀스 함수 호출)
      _startAppSequence();
    }

    // 🔴 새로 만드는 단계별 실행 함수
    Future<void> _startAppSequence() async {
      if (!mounted) return;

      // 1) 서버 핀 데이터 가져오기 → 2) 위치 초기화 → 3) 완료 즉시 지도 로딩 허용
      await _fetchServerPins();
      await _initLocation();

      if (!mounted) return;
      setState(() {
        _canLoadMap = true;
        _locationLoading = false;
      });
      }
  @override
  void dispose() {
    TripService.tripsRefreshNotifier.removeListener(_onTripsChanged);
    _positionStream?.cancel();
    _sheetController.dispose();
    super.dispose();
  }

  // ── GPS 권한 요청 + 현재 위치 가져오기 ──────────────────────
  Future<void> _initLocation() async {
    // 1. 위치 서비스 활성화 확인
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _locationLoading = false);
      _showLocationError('위치 서비스가 꺼져 있습니다.\n설정에서 위치 서비스를 켜주세요.');
      return;
    }

    // 2. 권한 확인
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _locationLoading = false);
        _showLocationError('위치 권한이 거부되었습니다.');
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      setState(() => _locationLoading = false);
      _showLocationError('위치 권한이 영구 차단되었습니다.\n설정에서 권한을 허용해주세요.');
      return;
    }

    // 3. 초기 위치 1회 획득 (스트림 구독 전)
    try {
      final initial = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      setState(() {
        _currentPosition = initial;
        _mapCenterLat = initial.latitude;
        _mapCenterLng = initial.longitude;
        _locationLoading = false;
      });
      _updateVisiblePins(initial.latitude, initial.longitude);
      await _refreshMapMarkers();
    } catch (_) {
      // 초기 픽스 실패 시 아래 스트림으로 보완
    }

    // 4. 실시간 위치 스트림 구독 시작
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 10, // 10미터 단위 갱신
      ),
    ).listen((position) {
      setState(() {
        _currentPosition = position;
        _mapCenterLat = position.latitude;
        _mapCenterLng = position.longitude;
        _locationLoading = false;
      });
      _updateVisiblePins(position.latitude, position.longitude);

      // 지도 컨트롤러가 준비됐다면 빨간 점 마커만 갱신 (카메라는 이동하지 않음)
      if (_mapController != null) {
        _refreshMapMarkers();
        setState(() {});
      }
    });
  }

  // ── 현재 위치로 카메라 이동 ──
  Future<void> _moveToMyLocation() async {
    if (_mapController == null || _currentPosition == null) return;
    _mapController!.setCenter(
      LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
    );
  }

  // ── 지도 영역 내 핀 필터링 (반경 5km) ──────────────────────
  void _updateVisiblePins(double centerLat, double centerLng, {double radiusMeters = 5000}) {
    setState(() {
      _mapCenterLat = centerLat;
      _mapCenterLng = centerLng;
      _visiblePins = globalPins.where((pin) {
        final distance = pin.distanceTo(centerLat, centerLng);
        return distance <= radiusMeters;
      }).toList();
    });
  }

  // ── 지도에 표시할 마커 리스트 반환 (선언형 방식) ──────────────────────
  List<Marker> _getMapMarkers() {
    final List<Marker> markers = [];

    // globalPins의 핀 마커 추가
    for (final pin in globalPins) {
      markers.add(Marker(
        markerId: pin.id,
        latLng: LatLng(pin.lat, pin.lng),
        infoWindowContent: '<div style="padding:5px; font-size:12px; color:#333;">${pin.cur}/${pin.max}명<br>@${pin.hostId}</div>',
      ));
    }

    // 내 위치 마커 추가 (카카오맵 스타일: 빨간 원 + 흰색 테두리)
    if (_currentPosition != null) {
      markers.add(Marker(
        markerId: 'my_location',
        latLng: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        // 따옴표 충돌을 방지하기 위해 Base64로 인코딩된 빨간 원 + 흰색 테두리 SVG
        markerImageSrc: "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIzMiIgaGVpZ2h0PSIzMiI+PGNpcmNsZSBjeD0iMTYiIGN5PSIxNiIgcj0iMTEiIGZpbGw9IiNFOTMzMjMiIHN0cm9rZT0iI0ZGRkZGRiIgc3Ryb2tlLXdpZHRoPSI0Ii8+PC9zdmc+",
        width: 24,
        height: 24,
      ));
    }

    return markers;
  }

  // ── 마커 강제 새로고침 (컨트롤러 통해 수동 갱신) ──────────────────────
  Future<void> _refreshMapMarkers() async {
    if (_mapController == null) return;
    await _mapController!.clear();
    _mapController!.addMarker(markers: _getMapMarkers());
  }

  // ── 마커 클릭 핸들러 ──
  void _onMarkerTap(String markerId) {
    // 내 위치 파란 점 클릭 시 무시
    if (markerId == 'my_location') return;
    setState(() {
      _activePinId = markerId;
      _selectedRideId = null;
    });
  }

  void _showLocationError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.red,
            behavior: SnackBarBehavior.floating));
  }

  // ── 현재 활성화된 핀의 RidePin 객체 ──
  RidePin? get _activePinData =>
      _activePinId == null ? null
          : _visiblePins.firstWhere((p) => p.id == _activePinId,
          orElse: () => globalPins.isNotEmpty ? globalPins.first : _visiblePins.isNotEmpty ? _visiblePins.first : globalPins.first);

  @override
  Widget build(BuildContext context) {
    // 핀 개수가 변하면 지도 즉시 새로고침
    if (_isMapReady && _lastPinCount != globalPins.length) {
      _lastPinCount = globalPins.length;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // 방금 추가된 새 핀(리스트의 마지막 요소)의 좌표로 카메라 이동
        if (globalPins.isNotEmpty) {
          final newPin = globalPins.last;
          _mapController?.setCenter(LatLng(newPin.lat, newPin.lng));
          _mapController?.setLevel(4);
        }

        if (_currentPosition != null) {
          _updateVisiblePins(_currentPosition!.latitude, _currentPosition!.longitude);
        }

        // 마커 강제 새로고침
        await _refreshMapMarkers();
      });
    }

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Stack(
          children: [
            Column(children: [
              _buildHeader(),
              Expanded(child: _buildMapWithSheet()),
              // 이용 중 카드
              ActiveRideButton(
                state: _activeRideState,
                onTap: () => setState(() => _showActiveDetail = true),
              ),
            ]),
            if (_showNotifications) _buildNotificationOverlay(),
            if (_showActiveDetail)
              ActiveRideSheet(
                state: _activeRideState,
                onClose: () => setState(() => _showActiveDetail = false),
                onGoToChat: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ActiveTabChatBridge(
                        hostId: _activeRideState.activeRide!.hostId,
                        dept: _activeRideState.activeRide!.dept,
                        dest: _activeRideState.activeRide!.dest,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // ── 헤더 ──
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Row(children: [  // 로고, 알림, 프로필
            RichText(text: const TextSpan(
              style: TextStyle(fontSize: 26, letterSpacing: 2, fontWeight: FontWeight.w900),
              children: [
                TextSpan(text: 'TAXI', style: TextStyle(color: AppColors.secondary)),
                TextSpan(text: 'MATE', style: TextStyle(color: AppColors.primary)),
              ],
            )),
            const Spacer(),
            Stack(children: [
              IconButton(
                icon: Icon(
                  _showNotifications ? Icons.notifications : Icons.notifications_outlined,
                  color: _showNotifications ? AppColors.primary : AppColors.secondary,
                ),
                onPressed: () => setState(() => _showNotifications = !_showNotifications),
              ),
              Positioned(top: 8, right: 8,
                  child: Container(width: 8, height: 8,
                      decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle))),
            ]),
            GestureDetector(
              onTap: () => widget.onTabChange?.call(4),
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: AppColors.bg, shape: BoxShape.circle, border: Border.all(color: AppColors.border)),
                child: const Icon(Icons.person, color: AppColors.gray, size: 22),
              ),
            ),
          ]),
          const SizedBox(height: 10,),  // 여백
          Row(children: [ // 검색창 + 버튼 행 추가
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  final result = await Navigator.push<Map<String, dynamic>>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LocationSearchScreen(title: '지역'),
                    ),
                  );
                  if (result != null) {
                    final lat = result['lat'] as double;
                    final lng = result['lng'] as double;
                    _mapController?.setCenter(LatLng(lat, lng));
                    _updateVisiblePins(lat, lng);
                    await _refreshMapMarkers();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    const Icon(Icons.search, color: AppColors.gray, size: 18),
                    const SizedBox(width: 8),
                    const Text('지역 검색...',
                        style: TextStyle(fontSize: 13, color: AppColors.gray)),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => widget.onGoToCreate?.call(),
              child: Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 24),
              ),
            ),
          ]),

        ],
      ),
    );
  }



  // ── 지도 + 드래그 시트 ──
  Widget _buildMapWithSheet() {
    final activePin = _activePinData;
    final List<RidePin> displayPins = (_activePinId != null && activePin != null)
        ? _visiblePins.where((p) => p.dept == activePin.dept).toList()
        : _visiblePins;

    return Stack(children: [
      // 지도 준비 전에는 플레이스홀더만 렌더링해 로딩 중복 노출 방지
      _canLoadMap ? _buildKakaoMap() : _buildMapPlaceholder(),

      // 수동 새로고침 (내 위치 버튼 위)
      if (_canLoadMap)
        Positioned(
          bottom: _activePinId != null ? 370 : 64,
          right: 16,
          child: FloatingActionButton.small(
            heroTag: 'refresh_btn',
            backgroundColor: Colors.white,
            elevation: 4,
            onPressed: () {
              _fetchServerPins();
            },
            child: const Icon(Icons.refresh, color: AppColors.primary, size: 22),
          ),
        ),

      // 내 위치 버튼
      if (_canLoadMap)
        Positioned(
          bottom: _activePinId != null ? 320 : 14,
          right: 16,
          child: FloatingActionButton.small(
            heroTag: 'location_btn',
            backgroundColor: Colors.white,
            elevation: 4,
            onPressed: _moveToMyLocation,
            child: const Icon(Icons.my_location, color: AppColors.primary, size: 22),
          ),
        ),

      // 핀 목록 시트
      if (_activePinId != null)
        DraggableScrollableSheet(
          controller: _sheetController,
          initialChildSize: 0.45,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          snap: true,
          snapSizes: const [0.3, 0.45, 0.85],
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, -4))],
              ),
              child: Column(children: [
                _buildSheetHeader(sheetListCount: displayPins.length),
                Expanded(
                  child: displayPins.isEmpty
                      ? ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          children: const [
                            SizedBox(height: 120),
                            Center(
                              child: Text(
                                '이 지역에 동승 핀이 없습니다.',
                                style: TextStyle(color: AppColors.gray),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: displayPins.length,
                          itemBuilder: (_, i) => _buildRideCard(displayPins[i]),
                        ),
                ),
              ]),
            );
          },
        ),
    ]);
  } // 🔴 _buildMapWithSheet 함수는 여기서 완전히 끝납니다! 🔴

    // 🔴 _buildMapWithSheet와 완전히 독립된 새로운 함수입니다! 🔴
    Widget _buildMapPlaceholder() {
      return Container(
        color: AppColors.bg, // 배경색
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 빙글빙글 돌아가는 로딩 인디케이터
              CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 3,
              ),
              SizedBox(height: 16),
              Text(
                '지도를 안전하게 불러오는 중입니다...',
                style: TextStyle(
                  color: AppColors.gray,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '잠시만 기다려 주세요.',
                style: TextStyle(
                  color: AppColors.gray,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }


  // -- 카카오맵 위젯 -----------------------------------------
  Widget _buildKakaoMap() {
    // 웹 확인용에서는 지도 생략(카카오맵이 앱에서만 지원)
    if (kIsWeb) {
      return Container(
        color: Colors.grey[200],
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                '지도는 모바일에서 확인 가능합니다',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    // 초기 카메라 위치: GPS 로딩 전엔 서울시청, 로딩 후엔 내 위치
    final initialCenter = LatLng(_mapCenterLat, _mapCenterLng);

    return KakaoMap(
      key: const ValueKey('kakao_map_stable'),
      center: initialCenter,
      markers: _getMapMarkers().toList(),
      onMapCreated: (controller) async {
        _mapController = controller;

        // GPS 위치가 이미 로딩됐다면 해당 위치로 이동
        if (_currentPosition != null) {
          await _moveToMyLocation();
        }

        // 지도 준비 완료 상태 업데이트
        setState(() => _isMapReady = true);
      },
      onMarkerTap: (markerId, latLng, zoomLevel) {
        _onMarkerTap(markerId);
      },
      onMapTap: (latLng) {
        if (_activePinId != null) {
          setState(() { _activePinId = null; _selectedRideId = null; });
        }
        if (_showNotifications) {
          setState(() => _showNotifications = false);
        }
      },
      currentLevel: 5,
    );
  }

  // -- 시트 헤더 --
  Widget _buildSheetHeader({required int sheetListCount}) {
    final pinData = _activePinData;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Column(children: [
        GestureDetector(
          onTap: () {
            final current = _sheetController.size;
            final targetSize = current >= 0.8 ? 0.45 : 0.85;
            _sheetController.animateTo(targetSize,
                duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
          },
          behavior: HitTestBehavior.translucent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ),
        Row(children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('동승 모집 목록',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.secondary)),
              if (pinData != null)
                Text('${pinData.dept} 주변 $sheetListCount팀',
                    style: const TextStyle(fontSize: 11, color: AppColors.gray)),
            ],
          ),
          const Spacer(),
          // 거리순 정렬 버튼
          GestureDetector(
            onTap: () {
              setState(() {
                _visiblePins.sort((a, b) =>
                    a.distanceTo(_mapCenterLat, _mapCenterLng)
                        .compareTo(b.distanceTo(_mapCenterLat, _mapCenterLng)));
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: AppColors.bg, borderRadius: BorderRadius.circular(100),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text('📍 거리순', style: TextStyle(fontSize: 11, color: AppColors.gray)),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() { _activePinId = null; _selectedRideId = null; }),
            child: const Icon(Icons.close, color: AppColors.gray, size: 20),
          ),
        ]),
      ]),
    );
  }

  // -- 동승 카드 (매칭 탭 검색 카드와 동일한 지도 핀 모집글 레이아웃) --
  Widget _buildRideCard(RidePin pin) {
    final isSelected = _selectedRideId == pin.id;

    return GestureDetector(
      onTap: () {
        setState(() => _selectedRideId = isSelected ? null : pin.id);
        if (!isSelected) {
          _mapController?.setCenter(LatLng(pin.lat, pin.lng));
          _mapController?.setLevel(4);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryLight : Colors.white,
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AppColors.bg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person, color: AppColors.gray, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '@${pin.hostId}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              pin.dept,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              '→',
                              style: TextStyle(
                                color: AppColors.secondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              pin.dest,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.secondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      const Text('출발', style: TextStyle(fontSize: 9, color: Colors.white70)),
                      Text(
                        pin.time,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ...List.generate(
                  pin.max,
                  (j) => Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: j < pin.cur ? AppColors.primary : AppColors.bg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: j < pin.cur ? AppColors.primary : AppColors.border,
                      ),
                    ),
                    child: j < pin.cur
                        ? const Icon(Icons.person, color: Colors.white, size: 13)
                        : null,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${pin.cur}/${pin.max}명',
                  style: const TextStyle(fontSize: 11, color: AppColors.gray),
                ),
                if (pin.isFull)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: const Text(
                      '마감',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.gray,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              child: isSelected
                  ? Column(
                      children: [
                        const SizedBox(height: 12),
                        const Divider(height: 1, color: AppColors.border),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ListenableBuilder(
                            listenable: globalActiveRideState,
                            builder: (context, _) {
                              final int tripId =
                                  int.tryParse(pin.id.toString()) ?? 0;
                              final bool isAlreadyJoined =
                                  globalActiveRideState.waitingPins
                                          .any((p) => p.id == tripId) ||
                                      globalActiveRideState.myPins
                                          .any((p) => p.id == tripId);

                              return ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: pin.isMine ||
                                          pin.isFull ||
                                          isAlreadyJoined
                                      ? const Color(0xFFE5E7EB)
                                      : AppColors.primary,
                                  disabledBackgroundColor:
                                      const Color(0xFFE5E7EB),
                                  disabledForegroundColor: AppColors.gray,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                onPressed: pin.isMine ||
                                        pin.isFull ||
                                        isAlreadyJoined
                                    ? null
                                    : () {
                                        if (globalActiveRideState.activePinCount >= 2) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                '동시에 최대 2개의 동승에만 참여할 수 있습니다.',
                                              ),
                                              backgroundColor: AppColors.red,
                                            ),
                                          );
                                          return;
                                        }
                                        Navigator.push(
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
                                      },
                                child: Text(
                                  pin.isMine
                                      ? '내가 생성한 모집글입니다'
                                      : isAlreadyJoined
                                          ? '이미 참여한 핀입니다'
                                          : pin.isFull
                                              ? '마감된 팀입니다'
                                              : '참여하기',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  // -- 알림 패널 --
  Widget _buildNotificationOverlay() {
    return Positioned(
      top: 0, right: 12, left: 12,
      child: Material(
        elevation: 8, borderRadius: BorderRadius.circular(16), color: Colors.white,
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                child: Row(children: [
                  const Text('알림', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  TextButton(
                    onPressed: () {},
                    style: TextButton.styleFrom(foregroundColor: AppColors.gray),
                    child: const Text('모두 읽음', style: TextStyle(fontSize: 11)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: AppColors.gray),
                    onPressed: () => setState(() => _showNotifications = false),
                  ),
                ]),
              ),
              const Divider(height: 1, color: AppColors.border),
              if (_dummyNotifications.isEmpty)
                const SizedBox(
                  height: 160,
                  child: Center(
                    child: Text(
                      '새로운 알림이 없습니다.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.gray,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              else
                ..._dummyNotifications.map((n) => InkWell(
                      onTap: () => setState(() => _showNotifications = false),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(n['icon']!, style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(n['msg']!, style: const TextStyle(fontSize: 13, color: AppColors.secondary)),
                                  const SizedBox(height: 2),
                                  Text(n['time']!, style: const TextStyle(fontSize: 11, color: AppColors.gray)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}
