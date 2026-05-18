// ============================================================
// lib/screens/tabs/active_tab.dart
// ============================================================
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/colors.dart';
import '../../service/trip_service.dart';
import '../../service/auth_session.dart';
import 'message_tab.dart' hide SettlementMessage;
import '../../service/notification_service.dart';
import 'dart:async'; // StreamSubscription 사용을 위해 추가
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import 'message_tab.dart' as chat;
import '../../service/settlement_service.dart'; // 🌟 추가
import '../../config/app_config.dart';

// ============================================================
// 열거형 & 모델
// ============================================================

enum PinPhase { open, closed }
enum RidePhase { riding, settled, completed }

class ActiveRidePin {
  final int id;
  final String hostId;
  final String dept;
  final String dest;
  final DateTime departTime;
  final int max;
  final int cur;
  final bool isMine;
  final String? kakaoPayLink;
  final RidePhase phase;
  final PinPhase pinPhase;

  const ActiveRidePin({
    required this.id,
    required this.hostId,
    required this.dept,
    required this.dest,
    required this.departTime,
    required this.max,
    required this.cur,
    this.isMine = false,
    this.kakaoPayLink,
    this.phase = RidePhase.riding,
    this.pinPhase = PinPhase.open,
  });

  // 📍 서버 연동: JSON 데이터를 모델로 변환
  factory ActiveRidePin.fromJson(Map<String, dynamic> json) {
    final parsedTime = DateTime.parse(json['depart_time']).toLocal();
    final hostId = (json['host_nickname'] ?? '익명').toString();

    // DB의 방장 닉네임과 내 닉네임이 같으면 무조건 내가 만든 핀으로 처리!
    final isMyPin = json['is_mine'] == true || hostId == (AuthSession.username ?? '');

    return ActiveRidePin(
      id: json['id'],
      hostId: hostId,
      dept: json['depart_name'],
      dest: json['arrive_name'],
      departTime: parsedTime,
      max: json['capacity'],
      cur: json['current_count'],
      isMine: isMyPin, // 👈 보강된 필터링 로직 적용
      kakaoPayLink: json['kakaopay_link'],
      phase: _mapStatusToPhase(json['status']),
      pinPhase: _mapStatusToPinPhase(json['status']),
    );
  }

  // 📍 백엔드 모델 상태값(OPEN, FULL, CLOSED, COMPLETED) 매핑
  static RidePhase _mapStatusToPhase(String? status) {
    if (status == 'OPEN' || status == 'FULL') return RidePhase.riding;
    if (status == 'CLOSED') return RidePhase.settled; // 정산 중
    if (status == 'COMPLETED') return RidePhase.completed; // 완료됨
    return RidePhase.riding;
  }

  static PinPhase _mapStatusToPinPhase(String? status) {
    if (status == 'CLOSED' || status == 'FULL' || status == 'COMPLETED') return PinPhase.closed;
    return PinPhase.open;
  }

  String get time => "${departTime.hour.toString().padLeft(2, '0')}:${departTime.minute.toString().padLeft(2, '0')}";
  String get date {
    final now = DateTime.now();
    if (departTime.year == now.year && departTime.month == now.month && departTime.day == now.day) return '오늘';
    final tmr = now.add(const Duration(days: 1));
    if (departTime.year == tmr.year && departTime.month == tmr.month && departTime.day == tmr.day) return '내일';
    return '${departTime.month}/${departTime.day}';
  }
}

 class ActiveRideState extends ChangeNotifier {
   bool _isDisposed = false;
   List<ActiveRidePin> _waitingPins = [];
   List<ActiveRidePin> _myPins = [];
   bool _isLoading = false;
// 🔽 [추가] 중복 알림 방지 및 만석 감지 UI 트리거용 변수
   final Set<int> _notifiedFullTripIds = {};
   void Function(int tripId)? onRoomFull;
   // 🆕 실시간 통신을 위한 채널 변수 (웹/앱 공용)
   WebSocketChannel? _channel;
   StreamSubscription? _wsSubscription; // 🆕 메모리 누수 방지를 위한 구독 객체

   List<ActiveRidePin> get waitingPins => _waitingPins;
   List<ActiveRidePin> get myPins => _myPins;
   bool get isLoading => _isLoading;

    int get activePinCount =>
        _myPins.where((p) => p.phase != RidePhase.completed).length +
        _waitingPins.where((p) => p.phase != RidePhase.completed).length;

    // 📍 기존 home_tab.dart와의 호환성을 위해 이름을 activeRide로 유지합니다.
    ActiveRidePin? get activeRide {
      final allRides = [..._myPins, ..._waitingPins]
        .where((p) => p.phase != RidePhase.completed).toList()
        ..sort((a, b) => a.departTime.compareTo(b.departTime));
      if (allRides.isEmpty) return null;
      return allRides.first;
    }


   // 🆕 1. 실시간 리스너 시작
   void initRealTimeListener(int tripId) {
     _stopListener(); // 중복 연결 방지

     // Django Channels 주소 (본인의 서버 설정에 맞게 수정)
     final wsUrl = 'ws://10.0.2.2:8000/ws/trip/$tripId/';

     try {
       _channel = WebSocketChannel.connect(Uri.parse(wsUrl)); // 변경된 패키지 적용
       _wsSubscription = _channel!.stream.listen((message) { // 구독 객체에 저장
         debugPrint('실시간 업데이트 신호 수신: $message');
         fetchActiveRides(); // 신호 오면 즉시 갱신
       }, onError: (err) {
         debugPrint('웹소켓 에러 발생: $err');
       });
     } catch (e) {
       debugPrint('웹소켓 연결 실패: $e');
     }
   }

   // 🆕 2. 리스너 중지
   void _stopListener() {
     _wsSubscription?.cancel(); // 🆕 수신 스트림 먼저 취소
     _wsSubscription = null;
     _channel?.sink.close();
     _channel = null;
   }

   // 📍 데이터 로드 및 리스너 자동 연결
   Future<void> fetchActiveRides() async {
     _isLoading = true;
     notifyListeners();
     try {
       final data = await TripService.getMyTrips(token: AuthSession.token ?? '');
       if (_isDisposed) return;
       final allPins = data.map((j) => ActiveRidePin.fromJson(j)).toList();

       _myPins = allPins.where((p) => p.isMine).toList();
       _waitingPins = allPins.where((p) => !p.isMine).toList();

       final currentRide = activeRide;
       if (currentRide != null) {
// ✅ 수정된 부분: 핀 상태가 '모집 완료(FULL)' 또는 '정산 중(CLOSED)'일 때만 알림 표시
         if (currentRide.pinPhase == PinPhase.closed) {
           NotificationService.showOngoingRide(
             title: '🚖 TaxiMate 이용 중',
             body: '${currentRide.time} 출발 | ${currentRide.dept} → ${currentRide.dest}',
           );
         } else {
           // 아직 OPEN(모집 중) 상태라면 상단 알림을 띄우지 않음
           NotificationService.cancelOngoingRide();
         }

         // 실시간 감시 시작 (상태 무관하게 웹소켓은 연결해야 방장의 '완료' 신호를 참여자가 받을 수 있음)
         initRealTimeListener(currentRide.id);
// 조건: 내가 방장이고, 인원이 꽉 찼고, 아직 출발 전(RIDING) 상태일 때
         if (currentRide.isMine &&
             currentRide.cur == currentRide.max &&
             currentRide.phase == RidePhase.riding) {

           // 이미 팝업을 띄운 방이 아니라면 UI에 다이얼로그 노출 요청
           if (!_notifiedFullTripIds.contains(currentRide.id)) {
             _notifiedFullTripIds.add(currentRide.id);

             // UI가 빌드 중일 때 예외가 발생하지 않도록 마이크로태스크로 안전하게 호출
             Future.microtask(() => onRoomFull?.call(currentRide.id));
           }
         }
       } else {
         NotificationService.cancelOngoingRide();
         _stopListener();
       }
     } catch (e) {
       debugPrint('이용 중 데이터 로드 실패: $e');
     } finally {
       if (!_isDisposed) {
         _isLoading = false;
         notifyListeners();
       }
     }
   }

   // 📍 2. 탑승 완료 처리 -> CLOSED 상태로 변경
   Future<void> completeBoarding(int tripId) async {
     final success = await TripService.updateTripStatus(
       token: AuthSession.token ?? '',
       tripId: tripId,
       status: 'CLOSED',
     );
     if (success) {
       await fetchActiveRides();
       // 🌟 갱신 신호 발사!
       _channel?.sink.add(jsonEncode({'type': 'trip_updated', 'message': '상태 업데이트'}));
     }
   }

   // 📍 3. 핀 모집 마감 -> FULL 상태로 변경
   Future<void> closePinRecruit(int tripId) async {
     final success = await TripService.updateTripStatus(
       token: AuthSession.token ?? '',
       tripId: tripId,
       status: 'FULL',
     );
     if (success) {
       await fetchActiveRides();
       // 🌟 갱신 신호 발사!
       _channel?.sink.add(jsonEncode({'type': 'trip_updated', 'message': '상태 업데이트'}));
     }
   }

   // 📍 4. 핀 삭제 및 신청 취소
   Future<void> deleteOrCancelTrip(int tripId, {required bool isMine}) async {
     bool success = false;
     if (isMine) {
       final result = await TripService.deleteTrip(
         token: AuthSession.token ?? '',
         tripId: tripId,
       );
       success = result['success'] == true;
     } else {
       final result = await TripService.leaveTrip(
         token: AuthSession.token ?? '',
         tripId: tripId,
       );
       success = result['success'] == true;
     }
     if (success) {
       await fetchActiveRides();
       // 🌟 갱신 신호 발사!
       _channel?.sink.add(jsonEncode({'type': 'trip_updated', 'message': '상태 업데이트'}));
     }
   }
// 🌟 이 함수를 추가하세요!
  void reset() {
    _stopListener();
    _waitingPins.clear();
    _myPins.clear();
    _isLoading = false;
    _notifiedFullTripIds.clear();
    // dispose()와 달리 객체는 살려두고 내용물만 비웁니다.
    notifyListeners();
  }
   @override
   void dispose() {
     _isDisposed = true;
     _stopListener();
     super.dispose();
   }
 }
final globalActiveRideState = ActiveRideState();

// ============================================================
// 정산 메시지 클래스
// ============================================================
class SettlementMessage {
  final int totalFare, perPerson, memberCount;
  final String? kakaoPayLink;
  final String hostId;
  final File? imageFile;

  SettlementMessage({
    required this.totalFare,
    required this.perPerson,
    required this.memberCount,
    this.kakaoPayLink,
    required this.hostId,
    this.imageFile,
  });
}

final settlementMessageNotifier = ValueNotifier<SettlementMessage?>(null);

// ============================================================
// 이용 중 시트
// ============================================================
class ActiveRideSheet extends StatefulWidget {
  final ActiveRideState state;
  final VoidCallback onClose;
  final VoidCallback? onGoToChat;

  const ActiveRideSheet({
    super.key,
    required this.state,
    required this.onClose,
    this.onGoToChat,
  });

  @override
  State<ActiveRideSheet> createState() => _ActiveRideSheetState();
}

class _ActiveRideSheetState extends State<ActiveRideSheet> {
  final DraggableScrollableController _sheetCtrl = DraggableScrollableController();

  ActiveRideState get _s => widget.state;
  ActiveRidePin? get ride => _s.activeRide;

  @override
  void dispose() {
    _sheetCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ride == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _s,
      builder: (_, __) => GestureDetector(
        onTap: widget.onClose,
        child: Container(
          color: Colors.black.withOpacity(0.4),
          child: DraggableScrollableSheet(
            controller: _sheetCtrl,
            initialChildSize: 0.55,
            minChildSize: 0.4,
            maxChildSize: 0.85,
            snap: true,
            snapSizes: const [0.4, 0.55, 0.85],
            builder: (context, scrollController) {
              return GestureDetector(
                onTap: () {},
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      _buildHeader(),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(20),
                          children: [
                            _buildTeamCard(ride!),
                            const SizedBox(height: 14),
                            _buildMemberCard(ride!),
                            const SizedBox(height: 14),
                            _buildActionButtons(context, ride!),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: widget.onClose,
            behavior: HitTestBehavior.translucent,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ),
          Row(
            children: [
              const RidingBadge(),
              const Spacer(),
              GestureDetector(
                onTap: widget.onClose,
                child: const Icon(Icons.close, color: AppColors.gray, size: 22),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTeamCard(ActiveRidePin r) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('팀 정보', style: TextStyle(fontSize: 12, color: AppColors.gray, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: [
              _profileCircle(44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('@${r.hostId}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.secondary)),
                    const SizedBox(height: 4),
                    _routeRow(r.dept, r.dest),
                  ],
                ),
              ),
              _timeBox(r.time, r.date),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMemberCard(ActiveRidePin r) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('인원 현황', style: TextStyle(fontSize: 12, color: AppColors.gray, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: [
              ..._seatIndicators(r.max, r.cur),
              const SizedBox(width: 8),
              Text('${r.cur}/${r.max}명 탑승', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.secondary)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: r.cur / r.max,
              backgroundColor: AppColors.primaryLight,
              color: AppColors.primary,
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, ActiveRidePin r) {
    final bool isPastDeparture = DateTime.now().isAfter(r.departTime);

    return Column(
      children: [
        if (r.phase == RidePhase.riding) ...[
          const SizedBox(height: 10),
          if (r.isMine)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPastDeparture ? AppColors.primary : AppColors.gray.withOpacity(0.3),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: isPastDeparture ? () => _confirmBoarding(context, r.id, _s) : null,
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: Text(
                  isPastDeparture ? '탑승 확인 완료' : '출발 시각 이후 활성화',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            )
          else
            _waitingBox(isPastDeparture ? '대표자의 탑승 확인을 기다리는 중...' : '출발 시각(${r.time}) 이후 정산이 시작됩니다'),
        ] /*else if (r.phase == RidePhase.settled) ...[
          const SizedBox(height: 10),
          if (r.isMine) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _goToReceiptShare(context, r),
                icon: const Icon(Icons.receipt_long_outlined, size: 16),
                label: const Text('결제 내역 공유하기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ] else
            _waitingBox('대표자의 결제 내역 공유를 기다리는 중...'),
        ] else if (r.phase == RidePhase.completed) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _goToChatDialog(context),
              icon: const Icon(Icons.chat_bubble_outline, size: 16),
              label: const Text('채팅방으로 이동하여 정산 완료하기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ],*/
      ],
    );
  }

  Widget _waitingBox(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
    child: Center(child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.gray))),
  );

// 📍 _ActiveRideSheetState 내부의 _goToReceiptShare 함수를 이 코드로 교체합니다.
  void _goToReceiptShare(BuildContext context, ActiveRidePin r) async {
    // 1️⃣ 서버에서 방 정보를 조회하는 동안 화면이 멈춘 것처럼 보이지 않게 로딩 창을 띄웁니다.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );

    int? realChatRoomId;
    try {
      // 2️⃣ 서버 API를 호출하여 내가 속한 전체 채팅방 리스트를 받아옵니다.
      final data = await TripService.getChatRooms(token: AuthSession.token ?? '');

      // 3️⃣ 현재 이용 중인 방 번호(r.id)와 일치하는 진짜 채팅방 ID(map['id'])를 맵핑합니다.
      for (var item in data) {
        final map = Map<String, dynamic>.from(item as Map);
        if (map['trip_id'] == r.id) {
          realChatRoomId = map['id'] as int?;
          break;
        }
      }
    } catch (e) {
      debugPrint('정산 화면 이동 중 채팅방 조회 실패: $e');
    }

    // 통신이 끝났으므로 띄워두었던 로딩 팝업을 먼저 안전하게 닫아줍니다.
    if (!mounted) return;
    Navigator.pop(context);

    // 예외 처리: 만약 알 수 없는 이유로 매칭되는 채팅방 ID를 확보하지 못했다면 스낵바 알림 후 중단합니다.
    if (realChatRoomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('연결된 채팅방을 찾을 수 없습니다.'), backgroundColor: AppColors.red),
      );
      return;
    }

    // 4️⃣ 🎉 드디어 진짜 대화방 ID(realChatRoomId)를 확보했으므로 파라미터에 장착하여 정산 화면으로 이동합니다!
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReceiptShareScreen(
          activeRide: r,
          chatRoomId: realChatRoomId!, // 🌟 여기에 빠졌던 필수 변수가 전달되면서 에러가 해결됩니다!
          onSent: () => widget.onGoToChat?.call(),
        ),
      ),
    );
  }
  void _goToChatDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('채팅방으로 이동', style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('채팅방으로 이동하여 정산하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, elevation: 0),
            onPressed: () {
              Navigator.pop(context);
              widget.onClose();
              widget.onGoToChat?.call();
            },
            child: const Text('이동하기'),
          ),
        ],
      ),
    );
  }

  Widget _profileCircle(double size) => Container(
    width: size, height: size,
    decoration: BoxDecoration(color: AppColors.bg, shape: BoxShape.circle, border: Border.all(color: AppColors.border)),
    child: Icon(Icons.person, color: AppColors.gray, size: size * 0.55),
  );

  Widget _routeRow(String dept, String dest) => Row(
    children: [
      Flexible(child: Text(dept, style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('→', style: TextStyle(color: AppColors.textSub, fontWeight: FontWeight.w700))),
      Flexible(child: Text(dest, style: const TextStyle(fontSize: 12, color: AppColors.secondary), overflow: TextOverflow.ellipsis)),
    ],
  );

  Widget _timeBox(String time, String date) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
    child: Column(
      children: [
        Text(date, style: const TextStyle(fontSize: 9, color: Colors.white70)),
        Text(time, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
      ],
    ),
  );

  List<Widget> _seatIndicators(int max, int cur) => List.generate(
    max,
        (j) => Container(
      width: 22, height: 22,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: j < cur ? AppColors.primary : AppColors.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: j < cur ? AppColors.primary : AppColors.border),
      ),
      child: j < cur ? const Icon(Icons.person, color: Colors.white, size: 13) : null,
    ),
  );
}

// ============================================================
// 결제 내역 공유 화면 (실제 서버 API 호출 연결 완료)
// ============================================================
class ReceiptShareScreen extends StatefulWidget {
  final ActiveRidePin activeRide;
  final int chatRoomId; // 🌟 1. 이 줄 추가
  final VoidCallback onSent;

  const ReceiptShareScreen({
    super.key,
    required this.activeRide,
    required this.chatRoomId, // 🌟 2. 이 줄 추가
    required this.onSent,
  });
  @override
  State<ReceiptShareScreen> createState() => _ReceiptShareScreenState();
}

class _ReceiptShareScreenState extends State<ReceiptShareScreen> {
  File? _receiptImage;
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _totalCtrl = TextEditingController(text: '25000');
  late TextEditingController _perPersonCtrl;
  bool _isLoading = false;
  bool _sent = false;

  int get _memberCount => widget.activeRide.cur;
  int get _totalFare => int.tryParse(_totalCtrl.text.replaceAll(',', '')) ?? 0;
  int get _perPerson => _memberCount > 0 ? (_totalFare / _memberCount).ceil() : 0;

  @override
  void initState() {
    super.initState();
    _perPersonCtrl = TextEditingController(text: _perPerson.toString());
  }

  void _recalc() => setState(() => _perPersonCtrl.text = _perPerson.toString());

  @override
  void dispose() {
    _totalCtrl.dispose();
    _perPersonCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickReceiptImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(source: source, imageQuality: 80, maxWidth: 512, maxHeight: 512);
      if (picked != null) setState(() => _receiptImage = File(picked.path));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('사진을 불러올 수 없습니다.')));
    }
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
              const Align(alignment: Alignment.centerLeft, child: Text('영수증 사진 선택', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.secondary))),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
                title: const Text('갤러리에서 선택', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () { Navigator.pop(context); _pickReceiptImage(ImageSource.gallery); },
              ),
              const Divider(color: AppColors.border, height: 1),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: Color(0xFF4A6FFF)),
                title: const Text('카메라로 촬영', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () { Navigator.pop(context); _pickReceiptImage(ImageSource.camera); },
              ),
              if (_receiptImage != null) ...[
                const Divider(color: AppColors.border, height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: AppColors.red),
                  title: const Text('영수증 삭제', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w600)),
                  onTap: () { Navigator.pop(context); setState(() => _receiptImage = null); },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppColors.secondary, size: 18), onPressed: () => Navigator.pop(context)),
        title: const Text('결제 내역 공유', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.secondary)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 요약 카드
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                      child: Row(
                        children: [
                          Container(width: 40, height: 40, decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle), child: const Icon(Icons.local_taxi, color: AppColors.primary)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${widget.activeRide.dept} → ${widget.activeRide.dest}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.secondary)),
                                const SizedBox(height: 4),
                                Text('${widget.activeRide.date} ${widget.activeRide.time} 출발  •  총 ${widget.activeRide.cur}명', style: const TextStyle(fontSize: 11, color: AppColors.gray)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (!kIsWeb) ...[
                      const Text('영수증 사진', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.secondary)),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: _showImagePickerSheet,
                        child: Container(
                          width: double.infinity, height: 140,
                          decoration: BoxDecoration(color: _receiptImage != null ? AppColors.primaryLight : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _receiptImage != null ? AppColors.primary : AppColors.border, width: _receiptImage != null ? 1.5 : 1)),
                          child: _receiptImage != null
                              ? ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.file(_receiptImage!, fit: BoxFit.cover))
                              : Column(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.add_photo_alternate_outlined, color: AppColors.gray, size: 36), SizedBox(height: 8), Text('영수증 사진 첨부', style: TextStyle(fontSize: 13, color: AppColors.gray))]),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    const Text('정산 금액', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.secondary)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Expanded(flex: 2, child: Text('총 택시 요금', style: TextStyle(fontSize: 13, color: AppColors.secondary))),
                              Expanded(flex: 3, child: TextField(controller: _totalCtrl, keyboardType: TextInputType.number, textAlign: TextAlign.right, onChanged: (_) => _recalc(), decoration: const InputDecoration(suffixText: '원', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10), isDense: true))),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Divider(color: AppColors.border),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Expanded(flex: 2, child: Text('탑승 인원', style: TextStyle(fontSize: 13, color: AppColors.secondary))),
                              Expanded(flex: 3, child: Text('${_memberCount}명', textAlign: TextAlign.right, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.secondary))),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Divider(color: AppColors.border),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Expanded(flex: 2, child: Text('1인당 정산 금액', style: TextStyle(fontSize: 13, color: AppColors.secondary, fontWeight: FontWeight.w700))),
                              Expanded(flex: 3, child: TextField(controller: _perPersonCtrl, keyboardType: TextInputType.number, textAlign: TextAlign.right, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary), decoration: const InputDecoration(suffixText: '원', filled: true, fillColor: AppColors.primaryLight, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10), isDense: true))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 유효성 검사 및 서버 전송
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _sent ? AppColors.gray : AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: (_sent || _isLoading) ? null : () => _sendSettlementRequest(context),
                  icon: _isLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Icon(_sent ? Icons.check : Icons.send_outlined, size: 18),
                  label: Text(_sent ? '정산 요청 완료' : '채팅방에 정산 요청 보내기', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 📍 실제 API 연동
  void _sendSettlementRequest(BuildContext context) async {
    if (!kIsWeb && _receiptImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('영수증 사진을 첨부해주세요.')));
      return;
    }

    setState(() => _isLoading = true);
final total = int.tryParse(_totalCtrl.text.replaceAll(',', '')) ?? _totalFare;
    final perPerson = int.tryParse(_perPersonCtrl.text.replaceAll(',', '')) ?? _perPerson;
    final token = AuthSession.token ?? '';

    try {
      // 1️⃣ 단계: 선택된 영수증 이미지 백엔드 파일 서버에 업로드
      final uploadResult = await SettlementService.uploadReceiptImage(
        token: token,
        tripId: widget.activeRide.id,
        imageFile: _receiptImage!,
        resetExisting: true, // 기존에 혹시 생성되어 있던 불완전한 정산은 무효화(Overwrite)
      );

      final receiptId = uploadResult['id'];
      if (receiptId == null || receiptId == 0) {
        throw Exception('영수증 업로드 번호(receipt_id)를 수신하지 못했습니다.');
      }

      // 2️⃣ 단계: 입력 폼에서 수정한 총 택시 요금 최종 확정
      await SettlementService.confirmReceiptAmount(
        token: token,
        receiptId: receiptId,
        totalAmount: total,
      );

      // 3️⃣ 단계: 핀 생성 시 유저가 등록해 두었던 카카오페이 링크 연동 및 등록
      await SettlementService.upsertPaymentChannel(
        token: token,
        tripId: widget.activeRide.id,
        kakaopayLink: widget.activeRide.kakaoPayLink ?? '',
      );

      // 4️⃣ 단계: 최종 정산서 리스트 데이터베이스 모델 생성 (팀원 인원수대로 쪼개진 영수증 맵 반환)
      final settlements = await SettlementService.createSettlements(
        token: token,
        tripId: widget.activeRide.id,
      );

      // 5️⃣ 단계: 🔗 대망의 채팅방 실시간 웹소켓 통로로 정산 카드 뿜어내기
      if (settlements.isNotEmpty) {
        final firstSettlementMap = Map<String, dynamic>.from(settlements.first as Map);

        // [검증] message_tab 규격 파일과 정상적으로 인코딩/디코딩 호환되는지 한 번 더 체크
        final verifiedMsg = chat.SettlementMessage.fromJson(firstSettlementMap);
        debugPrint('✅ message_tab 데이터 규격 일치 확인 완료: ${verifiedMsg.shareAmountText}');

        // 해당 채팅방 고유 웹소켓 주소 개설 및 임시 접속
        final encodedToken = Uri.encodeComponent(token);
        final wsUrl = Uri.parse('${AppConfig.wsBaseUrl}/ws/chat/${widget.chatRoomId}/?token=$encodedToken');
        final tempChatChannel = WebSocketChannel.connect(wsUrl);

        // ChatRoomScreen 리스너 수신 규격('settlement_request')에 맞게 패이로드 전송
        tempChatChannel.sink.add(jsonEncode({
          'type': 'settlement_request',
          'message': '정산 요청이 도착했습니다.',
          'settlement': firstSettlementMap, // message_tab이 렌더링할 로우 데이터 원본
          'sender': widget.activeRide.hostId,
          'sent_at': DateTime.now().toIso8601String(),
        }));

        // 신호탄 발송 후 소켓 즉시 안전하게 파괴 (리소스 누수 완벽 차단)
        await tempChatChannel.sink.close();
      }

      // 6️⃣ 단계: 카풀 이용 상태 완료('COMPLETED') 처리로 서버 최종 마감
      await TripService.updateTripStatus(
        token: token,
        tripId: widget.activeRide.id,
        status: 'COMPLETED',
      );

      // 7️⃣ 단계: 로컬 알림 상태 공유 노티파이어 세팅 (기존 코드 흐름 유지)
      settlementMessageNotifier.value = SettlementMessage(
        totalFare: total, perPerson: perPerson, memberCount: _memberCount,
        kakaoPayLink: widget.activeRide.kakaoPayLink, hostId: widget.activeRide.hostId, imageFile: _receiptImage,
      );

      if (!mounted) return;
      setState(() { _sent = true; _isLoading = false; });

      globalActiveRideState.fetchActiveRides(); // '이용중 바' 컴포넌트 실시간 동기화 새로고침
      widget.onSent(); // 채팅방 화면으로 유저를 자동 복귀/이동시키는 부모 콜백 실행

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('채팅방에 실시간 정산 카드를 발송했습니다 🎉'), backgroundColor: AppColors.primary)
      );

      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) Navigator.pop(context);
      });

    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('실시간 정산 연동 중 실패: $e'), backgroundColor: AppColors.red),
      );
    }
    }
  }

// ============================================================
// 이용 중 버튼
// ============================================================
class ActiveRideButton extends StatelessWidget {
  final ActiveRideState state;
  final VoidCallback onTap;

  const ActiveRideButton({super.key, required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (_, __) {
        final current = state.activeRide;
        if (current == null || current.phase == RidePhase.completed) {
          return const SizedBox.shrink();
        }

        return GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: AppColors.secondary.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Row(
              children: [
                const RidingBadge(),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(child: Text(current.dept, style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('→', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700))),
                      Flexible(child: Text(current.dest, style: const TextStyle(fontSize: 13, color: Colors.white70), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.keyboard_arrow_up, color: Colors.white, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================================
// 펄스 뱃지 (유지)
// ============================================================
class RidingBadge extends StatefulWidget {
  const RidingBadge({super.key});
  @override
  State<RidingBadge> createState() => _RidingBadgeState();
}
class _RidingBadgeState extends State<RidingBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.55, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(animation: _pulse, builder: (_, __) => Container(width: 7, height: 7, decoration: BoxDecoration(color: AppColors.success.withOpacity(_pulse.value), shape: BoxShape.circle, boxShadow: [BoxShadow(color: AppColors.success.withOpacity(0.35 * _pulse.value), blurRadius: 5)]))),
        const SizedBox(width: 5),
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: BorderRadius.circular(100), border: Border.all(color: AppColors.success.withOpacity(0.35))), child: const Text('이용 중', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.success))),
      ],
    );
  }
}

// ============================================================
// ActiveTab 본체
// ============================================================
class ActiveTab extends StatefulWidget {
  const ActiveTab({super.key});
  @override
  State<ActiveTab> createState() => _ActiveTabState();
}

class _ActiveTabState extends State<ActiveTab> with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  String? _selectedCardId;
  bool _showActiveDetail = false;
  final _state = globalActiveRideState;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() => setState(() => _selectedCardId = null));
    WidgetsBinding.instance.addPostFrameCallback((_) => _state.fetchActiveRides());
    TripService.tripsRefreshNotifier.addListener(_state.fetchActiveRides);
// 🤝 만석 신호가 오면 바깥의 _confirmBoarding을 호출하면서 현재 state(_state)를 전달!
  _state.onRoomFull = (tripId) {
    if (mounted) {
      _confirmBoarding(context, tripId, _state);
      }
      };
  }

  @override
  void dispose() {
    _state.onRoomFull = null;
    TripService.tripsRefreshNotifier.removeListener(_state.fetchActiveRides);
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _state,
      builder: (_, __) => Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildHeader(),
                  _buildTabBar(),
                  Expanded(
                    child: _state.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : TabBarView(controller: _tabCtrl, children: [_buildWaitingList(), _buildMyPinList()]),
                  ),
                  //if (!_state.isLoading && _state.activeRide != null)
                    //ActiveRideButton(state: _state, onTap: () => setState(() => _showActiveDetail = true)),
                ],
              ),
              if (_showActiveDetail)
                ActiveRideSheet(
                  state: _state,
                  onClose: () => setState(() => _showActiveDetail = false),
                  onGoToChat: () async {
                    final current = _state.activeRide;
                    if (current != null) {
                      // 1. 서버에서 채팅방 ID를 찾아오는 동안 잠깐 로딩 화면을 띄웁니다.
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                      );

                      try {
                        // 2. 서버에서 내가 속한 전체 채팅방 목록을 가져옵니다.
                        final data = await TripService.getChatRooms(token: AuthSession.token ?? '');
                        final rooms = data.map((item) => ChatRoomModel.fromJson(item)).toList();

                        // 3. 현재 이용 중인 핀(current.id)과 연결된 진짜 채팅방을 찾습니다.
                        ChatRoomModel? targetRoom;
                        for (var room in rooms) {
                          if (room.tripId == current.id) {
                            targetRoom = room;
                            break;
                          }
                        }

                        // 4. 로딩 화면 닫기
                        if (mounted) Navigator.pop(context);

                        // 5. 방을 찾았다면 진짜 채팅방(ChatRoomScreen)으로 이동!
                        if (targetRoom != null && mounted) {
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ChatRoomScreen(
                              room: targetRoom!, // 🌟 1. 느낌표(!) 추가
                              myNickname: AuthSession.username ?? '나',
                            )
                          ));
                        } else {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              // 🌟 2. backgroundColor를 Text 밖으로 이동!
                              const SnackBar(content: Text('채팅방을 찾을 수 없습니다.'), backgroundColor: AppColors.red)
                            );
                          }
                        }
                      } catch (e) {
                        if (mounted) Navigator.pop(context); // 오류 나도 로딩창은 닫기
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            // 🌟 3. backgroundColor를 Text 밖으로 이동!
                            const SnackBar(content: Text('네트워크 오류가 발생했습니다.'), backgroundColor: AppColors.red)
                          );
                        }
                      }
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() => Container(
      decoration: const BoxDecoration(color: Colors.white),
      padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            '이용 중',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.secondary)
          ),
          // 🔄 새로고침 버튼 추가
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.gray),
            onPressed: () {
              _state.fetchActiveRides();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('최신 상태로 새로고침 되었습니다.'),
                  duration: Duration(seconds: 1),
                  backgroundColor: AppColors.primary,
                ),
              );
            },
          ),
        ],
      ),
    );

  Widget _buildTabBar() => Container(
    color: Colors.white,
    child: TabBar(
      controller: _tabCtrl, labelColor: AppColors.primary, unselectedLabelColor: AppColors.gray, indicatorColor: AppColors.primary, indicatorWeight: 2.5,
      tabs: [
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Text('참여 중'), if (_state.waitingPins.isNotEmpty) ...[const SizedBox(width: 6), _countBadge(_state.waitingPins.length)]])),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Text('내가 만든 핀'), if (_state.myPins.isNotEmpty) ...[const SizedBox(width: 6), _countBadge(_state.myPins.length)]])),
      ],
    ),
  );

  Widget _buildWaitingList() {
    final pins = _state.waitingPins;
    if (pins.isEmpty) return _emptyState(icon: Icons.bookmark_border_outlined, title: '참여 신청한 팀이 없어요', sub: '홈에서 신청해보세요!');
    return RefreshIndicator(
      onRefresh: _state.fetchActiveRides,
      child: ListView.builder(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), itemCount: pins.length, itemBuilder: (_, i) => GestureDetector(onTap: () => setState(() => _selectedCardId = _selectedCardId == pins[i].id.toString() ? null : pins[i].id.toString()), child: _buildWaitingCard(pins[i]))),
    );
  }

  Widget _buildMyPinList() {
    final pins = _state.myPins;
    if (pins.isEmpty) return _emptyState(icon: Icons.location_on_outlined, title: '생성한 핀이 없어요', sub: '매칭 탭에서 새 핀을 만들어보세요!');
    return RefreshIndicator(
      onRefresh: _state.fetchActiveRides,
      child: ListView.builder(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), itemCount: pins.length, itemBuilder: (_, i) => GestureDetector(onTap: () => setState(() => _selectedCardId = _selectedCardId == pins[i].id.toString() ? null : pins[i].id.toString()), child: _buildMyPinCard(pins[i]))),
    );
  }

  Widget _buildWaitingCard(ActiveRidePin pin) {
    final isSelected = _selectedCardId == pin.id.toString();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: isSelected ? AppColors.primaryLight : Colors.white, border: Border.all(color: isSelected ? AppColors.primary : AppColors.border, width: isSelected ? 1.5 : 1), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _profileCircle(44), const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Text('@${pin.hostId}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.secondary)), const SizedBox(width: 6), _badge('신청 대기', AppColors.accent.withOpacity(0.1), AppColors.accent.withOpacity(0.3), AppColors.accent)]), const SizedBox(height: 4), _routeRow(pin)])),
              const SizedBox(width: 8), _timeBox(pin.time, pin.date),
            ],
          ),
          const SizedBox(height: 10),
          Row(children: [..._seatIndicators(pin), const SizedBox(width: 6), Text('${pin.cur}/${pin.max}명', style: const TextStyle(fontSize: 11, color: AppColors.gray))]),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            child: isSelected ? Column(children: [const SizedBox(height: 12), const Divider(height: 1, color: AppColors.border), const SizedBox(height: 12), SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () => _showCancelDialog(pin), style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('신청 취소', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))))]) : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildMyPinCard(ActiveRidePin pin) {
    final isSelected = _selectedCardId == pin.id.toString();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: isSelected ? AppColors.primaryLight : Colors.white, border: Border.all(color: isSelected ? AppColors.primary : AppColors.border, width: isSelected ? 1.5 : 1), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _profileCircle(44), const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Text('@${pin.hostId}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.secondary)), const SizedBox(width: 6), _badge('내 핀', AppColors.primaryLight, AppColors.primary.withOpacity(0.3), AppColors.primary)]), const SizedBox(height: 4), _routeRow(pin)])),
              const SizedBox(width: 8), _timeBox(pin.time, pin.date),
            ],
          ),
          const SizedBox(height: 10),
          Row(children: [..._seatIndicators(pin), const SizedBox(width: 6), Text('${pin.cur}/${pin.max}명', style: const TextStyle(fontSize: 11, color: AppColors.gray))]),
          if (pin.pinPhase == PinPhase.closed)
            Container(margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: AppColors.gray.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.gray.withOpacity(0.3))), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.lock_outline, size: 12, color: AppColors.gray), SizedBox(width: 4), Text('마감 완료된 핀', style: TextStyle(fontSize: 11, color: AppColors.gray, fontWeight: FontWeight.w600))])),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            child: isSelected ? Column(
              children: [
                const SizedBox(height: 12), const Divider(height: 1, color: AppColors.border), const SizedBox(height: 12),
                if (pin.pinPhase == PinPhase.open) ...[
                  SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () => _showFinishDialog(pin), style: OutlinedButton.styleFrom(foregroundColor: AppColors.primaryDark, side: const BorderSide(color: AppColors.primaryDark), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('모집 완료', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)))),
                  const SizedBox(height: 5),
                ],
                SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () => _showDeleteDialog(pin), style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('핀 삭제', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)))),
              ],
            ) : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  void _showCancelDialog(ActiveRidePin pin) {
    showDialog(context: context, builder: (_) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), title: const Text('신청 취소', style: TextStyle(fontWeight: FontWeight.w700)), content: Text('${pin.dept} → ${pin.dest}\n참여 신청을 취소할까요?'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('돌아가기')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white, elevation: 0), onPressed: () { Navigator.pop(context); _state.deleteOrCancelTrip(pin.id, isMine: false); }, child: const Text('신청 취소'))]));
  }
  void _showFinishDialog(ActiveRidePin pin) {
    showDialog(context: context, builder: (_) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), title: const Text('핀 모집 완료', style: TextStyle(fontWeight: FontWeight.w700)), content: Text('${pin.dept} → ${pin.dest}\n해당 핀의 모집을 완료할까요?'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('돌아가기')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryDark, foregroundColor: Colors.white, elevation: 0), onPressed: () { Navigator.pop(context); _state.closePinRecruit(pin.id); }, child: const Text('완료하기'))]));
  }
  void _showDeleteDialog(ActiveRidePin pin) {
    showDialog(context: context, builder: (_) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), title: const Text('핀 삭제', style: TextStyle(fontWeight: FontWeight.w700)), content: Text('${pin.dept} → ${pin.dest}\n생성한 핀을 삭제할까요?'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('돌아가기')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white, elevation: 0), onPressed: () { Navigator.pop(context); _state.deleteOrCancelTrip(pin.id, isMine: true); }, child: const Text('삭제하기'))]));
  }

  Widget _profileCircle(double size) => Container(width: size, height: size, decoration: BoxDecoration(color: AppColors.bg, shape: BoxShape.circle, border: Border.all(color: AppColors.border)), child: Icon(Icons.person, color: AppColors.gray, size: size * 0.55));
  Widget _routeRow(ActiveRidePin pin) => Row(children: [Flexible(child: Text(pin.dept, style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)), const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('→', style: TextStyle(color: AppColors.textSub, fontWeight: FontWeight.w700))), Flexible(child: Text(pin.dest, style: const TextStyle(fontSize: 12, color: AppColors.secondary), overflow: TextOverflow.ellipsis))]);
  Widget _timeBox(String time, String date) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)), child: Column(children: [Text(date, style: const TextStyle(fontSize: 9, color: Colors.white70)), Text(time, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white))]));
  List<Widget> _seatIndicators(ActiveRidePin pin) => List.generate(pin.max, (j) => Container(width: 22, height: 22, margin: const EdgeInsets.only(right: 4), decoration: BoxDecoration(color: j < pin.cur ? AppColors.primary : AppColors.bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: j < pin.cur ? AppColors.primary : AppColors.border)), child: j < pin.cur ? const Icon(Icons.person, color: Colors.white, size: 13) : null));
  Widget _badge(String text, Color bg, Color borderColor, Color textColor) => Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100), border: Border.all(color: borderColor)), child: Text(text, style: TextStyle(fontSize: 9, color: textColor, fontWeight: FontWeight.w700)));
  Widget _countBadge(int count) => Container(width: 18, height: 18, decoration: BoxDecoration(color: AppColors.gray.withOpacity(0.2), shape: BoxShape.circle), child: Center(child: Text('$count', style: const TextStyle(color: AppColors.gray, fontSize: 10, fontWeight: FontWeight.w800))));
  Widget _emptyState({required IconData icon, required String title, required String sub}) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(width: 72, height: 72, decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle), child: Icon(icon, color: AppColors.primary, size: 36)), const SizedBox(height: 16), Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.secondary)), const SizedBox(height: 6), Text(sub, style: const TextStyle(fontSize: 13, color: AppColors.gray))]));
}

void _confirmBoarding(BuildContext context, int tripId, ActiveRideState state) { // 👈 맨 뒤에 state 추가!
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('탑승 확인', style: TextStyle(fontWeight: FontWeight.w700)),
      content: const Text('모든 인원이 탑승했나요?\n확인하면 정산 단계로 넘어갑니다.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('아직이요')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, elevation: 0),
          onPressed: () {
            Navigator.pop(context);
            state.completeBoarding(tripId); // 👈 _s 대신 넘겨받은 state 원본을 호출!
          },
          child: const Text('탑승 완료'),
        ),
      ],
    ),
  );
}