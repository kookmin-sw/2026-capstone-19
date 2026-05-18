import '../../service/auth_session.dart';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import '../../utils/colors.dart';
import '../../utils/evaluation_helper.dart';
//import 'active_tab.dart';
import '../../service/trip_service.dart';
import '../../service/settlement_service.dart';
import '../../config/app_config.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../../service/notification_service.dart';

// ── 채팅방 모델 ──────────────────────────────────
class ChatRoomModel {
  final int id; // chat_room_id
  final int tripId; // 실제 trip_id
  final String name;
  final String lastMessage;
  final String time;
  final int unreadCount;
  final String pinnedNotice;
  final bool isLeader;

  const ChatRoomModel({
    required this.id,
    required this.tripId,
    required this.name,
    required this.lastMessage,
    required this.time,
    required this.unreadCount,
    required this.pinnedNotice,
    required this.isLeader,
  });

  factory ChatRoomModel.fromJson(Map<String, dynamic> json) {
    final dynamic rawLastMessage = json['last_message'];

    final String displayLastMessage;
    if (rawLastMessage == null) {
      displayLastMessage = "채팅방이 생성되었습니다.";
    } else if (rawLastMessage.toString().trim().isEmpty) {
      displayLastMessage = "사진을 보냈습니다.";
    } else {
      displayLastMessage = rawLastMessage.toString();
    }

    return ChatRoomModel(
      id: json['id'],
      tripId: json['trip_id'],
      name: json['trip_title'] ?? "새 채팅방",
      lastMessage: displayLastMessage,
      time: _formatDate(json['created_at'] ?? ""),
      unreadCount: json['unread_count'] ?? 0,
      pinnedNotice: json['pinned_notice'] ?? "만날 위치를 공유해주세요",
      isLeader: json['is_leader'] == true,
    );
  }

    static String _formatDate(String dateStr) {
      if (dateStr.isEmpty) return "";
      try {
        final DateTime dt = DateTime.parse(dateStr).toLocal();
        return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
      } catch (e) {
        return dateStr;
      }
    }
  }

class NoComposingUnderlineController extends TextEditingController {
  NoComposingUnderlineController();

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    return TextSpan(
      style: style,
      text: text,
    );
  }
}

// ── 메시지 모델 ──────────────────────────────────
class _Message {
  final String id, text, time, userId;
  final bool isMe, isLink, isSettlement, isSystem;
  final SettlementMessage? settlement;
  final File? imageFile;
  final String? imageUrl;

  const _Message({
    required this.id,
    required this.text,
    required this.time,
    required this.userId,
    required this.isMe,
    this.isLink = false,
    this.isSettlement = false,
    this.isSystem = false,
    this.settlement,
    this.imageFile,
    this.imageUrl,
  });
}

class SettlementMessage {
  final int settlementId;
  final int totalAmount;
  final int shareAmount;
  final String? receiptImageUrl;
  final String? paymentLink;
  final String status;

  const SettlementMessage({
    required this.settlementId,
    required this.totalAmount,
    required this.shareAmount,
    this.receiptImageUrl,
    this.paymentLink,
    required this.status,
  });

  factory SettlementMessage.fromJson(Map<String, dynamic> json) {
    String? channelLink;

    final paymentChannel = json['payment_channel'];
    if (paymentChannel is Map) {
      final paymentChannelMap = Map<String, dynamic>.from(paymentChannel);
      channelLink = paymentChannelMap['kakaopay_link']?.toString()
          ?? paymentChannelMap['payment_link']?.toString();
    }

    return SettlementMessage(
      settlementId: _toInt(json['settlement_id'] ?? json['id']),
      totalAmount: _toInt(json['total_amount']),
      shareAmount: _toInt(json['share_amount']),
      receiptImageUrl: json['receipt_image_url']?.toString()
          ?? json['image_url']?.toString(),
      paymentLink: json['kakaopay_link']?.toString()
          ?? json['payment_link']?.toString()
          ?? channelLink,
      status: json['status']?.toString() ?? 'REQUEST',
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String get totalAmountText => '${_formatWon(totalAmount)}원';
  String get shareAmountText => '${_formatWon(shareAmount)}원';
  bool get isCanceled => status.toUpperCase() == 'CANCELED';

  static String _formatWon(int value) {
    return value.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => ',',
    );
  }
}

class ChatTabBadgeController {
  static final ValueNotifier<bool> hasNewChat = ValueNotifier<bool>(false);

  static void setVisible(bool visible) {
    if (hasNewChat.value != visible) {
      hasNewChat.value = visible;
    }
  }
}

// ============================================================
// 채팅 탭 — 목록 화면
// ============================================================
class MessageTab extends StatefulWidget {
  const MessageTab({super.key});
  @override
  State<MessageTab> createState() => _MessageTabState();
}

class _MessageTabState extends State<MessageTab> {
  List<ChatRoomModel> _serverRooms = [];
  bool _isLoading = true;
  bool _isFetchingChatRooms = false;
  WebSocketChannel? _notificationChannel;
  static final Set<int> _roomsWithNewMessage = <int>{};
  static int? _openedRoomId;

  // 🌟 실제 로그인 환경에서는 이 닉네임을 전역 상태(UserProvider 등)에서 가져와야 합니다.
  // 현재는 TripService의 토큰 흐름에 맞춰 상수로 두거나 생성 시 받아와야 합니다.
  String get _currentUsername => AuthSession.username ?? '';

  void _onChatRoomsChanged() {
    _fetchChatRooms(showLoading: false);
  }

  void _syncChatTabBadge() {
    ChatTabBadgeController.setVisible(_roomsWithNewMessage.isNotEmpty);
  }

  @override
  void initState() {
    super.initState();
    _fetchChatRooms();

    TripService.chatRoomsRefreshNotifier.addListener(_onChatRoomsChanged);
    _connectNotificationWebSocket();
  }

  @override
  void dispose() {
    _notificationChannel?.sink.close();
    TripService.chatRoomsRefreshNotifier.removeListener(_onChatRoomsChanged);
    super.dispose();
  }

  Future<void> _fetchChatRooms({bool showLoading = true}) async {
    if (!mounted || _isFetchingChatRooms) return;

    _isFetchingChatRooms = true;

    if (showLoading) {
      setState(() => _isLoading = true);
    }

    try {
      final List<dynamic> data = await TripService.getChatRooms(
        token: AuthSession.token ?? '',
      );

      if (!mounted) return;

      setState(() {
        _serverRooms = data.map((item) => ChatRoomModel.fromJson(item)).toList();
        _isLoading = false;
      });
    } catch (e) {
      print('채팅방 목록 불러오기 실패: $e');

      if (mounted && showLoading) {
        setState(() => _isLoading = false);
      }
    } finally {
      _isFetchingChatRooms = false;
    }
  }

  void _connectNotificationWebSocket() {
    final token = AuthSession.token;

    if (token == null || token.isEmpty) {
      return;
    }

    final encodedToken = Uri.encodeComponent(token);
    final wsUrl = Uri.parse(
      '${AppConfig.wsBaseUrl}/ws/notifications/?token=$encodedToken',
    );

    _notificationChannel = WebSocketChannel.connect(wsUrl);

    _notificationChannel!.stream.listen(
      (data) {
        final decodedRaw = jsonDecode(data);

        if (decodedRaw is! Map) {
          return;
        }

        final decoded = Map<String, dynamic>.from(decodedRaw);
        final eventType = decoded['type']?.toString();

        if (eventType == 'chat_room_removed') {
          final roomId = int.tryParse(decoded['room_id']?.toString() ?? '');
          final tripId = int.tryParse(decoded['trip_id']?.toString() ?? '');

          if (mounted) {
            setState(() {
              _serverRooms.removeWhere(
                (room) =>
                    (roomId != null && room.id == roomId) ||
                    (tripId != null && room.tripId == tripId),
              );

              if (roomId != null) {
                _roomsWithNewMessage.remove(roomId);
              }
            });

            _syncChatTabBadge();
          }

          return;
        }

        if (eventType == 'chat_room_updated') {
          final int? roomId = decoded['room_id'] is int
              ? decoded['room_id'] as int
              : int.tryParse(decoded['room_id']?.toString() ?? '');
          final String lastMsg = decoded['last_message']?.toString() ?? '';

          final String sender = decoded['sender']?.toString() ?? '';
          final bool isMine = sender.isNotEmpty && sender == _currentUsername;

          if (!isMine && roomId != null && roomId != _openedRoomId && mounted) {

            NotificationService.showOngoingRide(
              title: '💬 $sender',
              body: lastMsg,
            );
            setState(() {
              _roomsWithNewMessage.add(roomId);
            });
            _syncChatTabBadge();
          }

          _fetchChatRooms(showLoading: false);
        }
      },
      onError: (error) {
        print('채팅방 목록 알림 WebSocket 오류: $error');
      },
      onDone: () {
        print('채팅방 목록 알림 WebSocket 종료');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _serverRooms.isEmpty
                      ? const Center(
                          child: Text(
                            '채팅방이 없습니다.',
                            style: TextStyle(
                              color: AppColors.gray,
                              fontSize: 13,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _serverRooms.length,
                          itemBuilder: (context, index) {
                            return _buildRoomTile(
                              context,
                              _serverRooms[index],
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: const Align(
        alignment: Alignment.centerLeft,
        child: Text('채팅', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.secondary)),
      ),
    );
  }

  Widget _buildRoomTile(BuildContext context, ChatRoomModel room) {
    final bool hasNewMessage =
      _roomsWithNewMessage.contains(room.id) || room.unreadCount > 0;
    return InkWell(
      onTap: () async {
        setState(() {
          _roomsWithNewMessage.remove(room.id);
        });

        _openedRoomId = room.id;

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatRoomScreen(
              room: room,
              myNickname: _currentUsername,
            ),
          ),
        );

        _openedRoomId = null;

        if (!mounted) return;
        setState(() {
          _roomsWithNewMessage.remove(room.id);
        });
        await _fetchChatRooms(showLoading: false);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
        child: Row(
          children: [
            _buildAvatar(hasNewMessage),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(room.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text(room.time, style: const TextStyle(fontSize: 11, color: AppColors.gray)),
                  ]),
                  const SizedBox(height: 4),
                  Text(room.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.gray)),
                ],
              ),
            ),
            if (hasNewMessage) _buildNewBadge(),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(bool hasUnread) {
    return Stack(children: [
      Container(
        width: 48, height: 48,
        decoration: BoxDecoration(color: AppColors.bg, shape: BoxShape.circle, border: Border.all(color: AppColors.border)),
        child: const Icon(Icons.person, color: AppColors.gray, size: 28),
      ),
      if (hasUnread)
        Positioned(bottom: 0, right: 0, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
    ]);
  }

  Widget _buildNewBadge() {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.red,
        shape: BoxShape.circle,
      ),
      child: const Text(
        'N',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

// ============================================================
// 채팅방 화면 (실시간 웹소켓 연동 버전)
// ============================================================
class ChatRoomScreen extends StatefulWidget {
  final ChatRoomModel room;
  final String myNickname;

  const ChatRoomScreen({super.key, required this.room, required this.myNickname});

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  WebSocketChannel? _channel;
  List<_Message> _messages = [];

  List<_Message> get _settlementMessages {
    return _messages
        .where((message) => message.isSettlement && message.settlement != null)
        .toList();
  }

  List<_Message> get _chatMessages {
    return _messages
        .where((message) => !(message.isSettlement && message.settlement != null))
        .toList();
  }
  final TextEditingController _inputCtrl = NoComposingUnderlineController();
  final ScrollController _scrollCtrl = ScrollController();
  // 테스트용 리더 토큰. 실제 배포에서는 로그인 후 저장된 토큰을 사용해야 함.
  //static const String _settlementToken = AuthSession.token ?? '';

  final ImagePicker _picker = ImagePicker();
  final TextEditingController _settlementAmountCtrl = TextEditingController();
  final TextEditingController _kakaoPayLinkCtrl = TextEditingController();

  int? _currentReceiptId;
  String? _currentReceiptImageUrl;
  bool _isSettlementProcessing = false;
  bool _showAttachPanel = false;
  bool _isNoticeExpanded = false;
  bool _hasShownEvaluation = false;
  late String _pinnedNotice;
  // 우선 주석처리
  // final ImagePicker _picker = ImagePicker();
  // bool _showAttachPanel = false;

  @override
  void initState() {
    super.initState();
    NotificationService.currentActiveRoomId = widget.room.id;
    _pinnedNotice = widget.room.pinnedNotice;
    _refreshCurrentRoomInfo();
    _loadChatMessages();
    _connectWebSocket();
    _loadPendingSettlementsForThisRoom();
  }

  Future<void> _refreshCurrentRoomInfo() async {
    try {
      final rooms = await TripService.getChatRooms(
        token: AuthSession.token ?? '',
      );

      final matchedRooms = rooms.where((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return _toInt(map['id']) == widget.room.id;
      }).toList();

      if (matchedRooms.isEmpty) return;

      final roomMap = Map<String, dynamic>.from(matchedRooms.first as Map);
      final latestNotice = roomMap['pinned_notice']?.toString() ?? '';

      if (!mounted || latestNotice.isEmpty) return;

      setState(() {
        _pinnedNotice = latestNotice;
      });

      if (!widget.room.isLeader &&
          !_hasShownEvaluation &&
          _pinnedNotice.contains('정산이 완료되었습니다')) {
        _hasShownEvaluation = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await EvaluationHelper.showGlobalEvaluationDialog(
            context: context,
            roomId: widget.room.id,
            tripId: widget.room.tripId,
            roomName: widget.room.name,
          );
        });
      }
    } catch (e) {
      print('채팅방 최신 공지 불러오기 실패: $e');
    }
  }

  void _connectWebSocket() {
    final token = Uri.encodeComponent(AuthSession.token ?? '');
    final wsUrl = Uri.parse('${AppConfig.wsBaseUrl}/ws/chat/${widget.room.id}/?token=$token');
    _channel = WebSocketChannel.connect(wsUrl);

    _channel!.stream.listen((data) {
      final decodedRaw = jsonDecode(data);

      if (decodedRaw is! Map) {
        return;
      }

      final decoded = Map<String, dynamic>.from(decodedRaw);

      if (!mounted) return;

      final shouldAutoScroll =
        decoded['sender'] == widget.myNickname || _isNearBottom();
      final messageType = decoded['type']?.toString();

      if (messageType == 'trip_deleted') {
          if (!mounted) return;

        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('매칭 삭제 안내'),
              content: Text(
                decoded['message']?.toString() ?? '리더가 매칭을 삭제했습니다.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('확인'),
                ),
              ],
            );
          },
        );

        if (!mounted) return;
        Navigator.of(context).pop();

        return;
      }

      setState(() {


        if (messageType == 'settlement_completed') {
          final notice = decoded['pinned_notice']?.toString();

          if (notice != null && notice.isNotEmpty) {
            _pinnedNotice = notice;
          } else {
            _pinnedNotice = '정산이 완료되었습니다.';
          }

          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            await _refreshCurrentRoomInfo();
            await _loadPendingSettlementsForThisRoom();
            TripService.notifyTripsChanged();
            TripService.notifyChatRoomsChanged();

            if (!widget.room.isLeader && !_hasShownEvaluation) {
              _hasShownEvaluation = true;
              await EvaluationHelper.showGlobalEvaluationDialog(
                context: context,
                roomId: widget.room.id,
                tripId: widget.room.tripId,
                roomName: widget.room.name,
              );
            }
          });

          return;
        }

        if (messageType == 'system_message') {
          _messages.add(
            _Message(
              id: 'msg_${decoded['message_id'] ?? DateTime.now().millisecondsSinceEpoch}',
              userId: 'system',
              text: decoded['message']?.toString() ?? '',
              time: _formatMessageTime(decoded['sent_at']?.toString()),
              isMe: false,
              isSystem: true,
            ),
          );

          return;
        }

        if (messageType == 'image_message') {
          _messages.add(
            _Message(
              id: 'msg_${decoded['message_id'] ?? DateTime.now().millisecondsSinceEpoch}',
              userId: decoded['sender']?.toString() ?? '',
              text: '',
              time: _formatMessageTime(decoded['sent_at']?.toString()),
              isMe: decoded['sender'] == widget.myNickname,
              imageUrl: _normalizeImageUrl(decoded['image_url']),
            ),
          );

          return;
        }

        if (messageType == 'settlement_request') {
          final settlementRaw = decoded['settlement'];

          final settlementJson = settlementRaw is Map
              ? Map<String, dynamic>.from(settlementRaw)
              : decoded;

          final rawSettlementId = settlementJson['id'];
          final settlementId = int.tryParse(rawSettlementId?.toString() ?? '');
          final messageId = settlementId != null
              ? 'settlement_$settlementId'
              : 'settlement_${decoded['message_id'] ?? DateTime.now().millisecondsSinceEpoch}';

          _messages.removeWhere(
            (message) => message.isSettlement && message.id == messageId,
          );

          _messages.add(
            _Message(
              id: messageId,
              userId: decoded['sender']?.toString() ?? 'system',
              text: decoded['message']?.toString() ?? '정산 요청이 도착했습니다.',
              time: _formatMessageTime(decoded['sent_at']?.toString()),
              isMe: false,
              isSettlement: true,
              settlement: SettlementMessage.fromJson(settlementJson),
            ),
          );
        } else {
          _messages.add(
            _Message(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              userId: decoded['sender']?.toString() ?? '',
              text: decoded['message']?.toString() ?? '',
              time: TimeOfDay.now().format(context),
              isMe: decoded['sender'] == widget.myNickname,
            ),
          );
        }
      });

      _scrollToBottomAfterLayout(force: shouldAutoScroll);
    });
  }

  Future<Map<String, dynamic>> _uploadChatImage(File imageFile) async {
    final uri = Uri.parse(
      '${AppConfig.apiBaseUrl}/chat/rooms/${widget.room.id}/images/',
    );

    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Token ${AuthSession.token ?? ''}';
    request.files.add(
      await http.MultipartFile.fromPath('image', imageFile.path),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    final bodyText = utf8.decode(response.bodyBytes);
    final contentType = response.headers['content-type'] ?? '';

    print('CHAT IMAGE UPLOAD STATUS: ${response.statusCode}');
    print('CHAT IMAGE UPLOAD CONTENT-TYPE: $contentType');
    print('CHAT IMAGE UPLOAD BODY: $bodyText');

    if (response.statusCode == 200 || response.statusCode == 201) {
      if (bodyText.trim().isEmpty) {
        return <String, dynamic>{};
      }

      if (contentType.contains('application/json')) {
        final decoded = jsonDecode(bodyText);

        if (decoded is Map<String, dynamic>) {
          return decoded;
        }

        return <String, dynamic>{};
      }

      return <String, dynamic>{};
    }

    throw Exception(
      '이미지 메시지 업로드 실패: ${response.statusCode} $bodyText',
    );
  }

  String? _normalizeImageUrl(dynamic value) {
    final raw = value?.toString().trim();

    if (raw == null || raw.isEmpty) {
      return null;
    }

    final baseUrl = AppConfig.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(raw);

    if (uri != null && uri.hasScheme) {
      final host = uri.host;

      final shouldReplaceHost = host == 'localhost' ||
          host == '127.0.0.1' ||
          host == '10.0.2.2' ||
          host == 'web' ||
          host == 'backend' ||
          host == 'db';

      if (shouldReplaceHost) {
        final path = uri.path.startsWith('/') ? uri.path : '/${uri.path}';
        final query = uri.hasQuery ? '?${uri.query}' : '';
        return '$baseUrl$path$query';
      }

      return raw;
    }

    if (raw.startsWith('/')) {
      return '$baseUrl$raw';
    }

    return '$baseUrl/$raw';
  }

  Future<void> _loadChatMessages() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.apiBaseUrl}/chat/rooms/${widget.room.id}/messages/'),
        headers: {
          'Authorization': 'Token ${AuthSession.token ?? ''}',
        },
      );

      if (response.statusCode != 200) {
        print('기존 채팅 메시지 불러오기 실패: ${response.statusCode} / ${response.body}');
        return;
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));

      if (decoded is! List) {
        return;
      }

      final loadedMessages = decoded.map<_Message>((item) {
        final map = Map<String, dynamic>.from(item as Map);

        final senderUsername = map['sender_username']?.toString() ?? '';
        final senderUserId = map['sender_user_id']?.toString() ?? '';
        final messageType = map['message_type']?.toString() ?? '';

        return _Message(
          id: 'msg_${map['id']}',
          userId: senderUsername.isNotEmpty ? senderUsername : senderUserId,
          text: map['message']?.toString() ?? '',
          time: _formatMessageTime(map['sent_at']?.toString()),
          isMe: senderUsername == widget.myNickname,
          isSystem: messageType == 'SYSTEM',
          imageUrl: messageType == 'IMAGE'
            ? _normalizeImageUrl(map['image_url'])
            : null,
        );
      }).toList();

      if (!mounted) return;

      setState(() {
        _messages.insertAll(0, loadedMessages);
      });

      _scrollToBottomAfterLayout(jump: true, force: true);
    } catch (e) {
      print('기존 채팅 메시지 불러오기 오류: $e');
    }
  }

  Future<void> _loadPendingSettlementsForThisRoom() async {
    try {
      final token = AuthSession.token ?? '';

      final settlements = widget.room.isLeader
          ? await SettlementService.getTripSettlements(
              token: token,
              tripId: widget.room.tripId,
            )
          : await SettlementService.getMyPaySettlements(
              token: token,
            );

      final roomSettlements = settlements.where((item) {
        final map = Map<String, dynamic>.from(item as Map);
        final tripId = _toInt(map['trip_id']);
        final status = map['status']?.toString();

        return tripId == widget.room.tripId &&
            ['REQUEST', 'LINK_OPENED', 'PAID_SELF', 'CONFIRMED'].contains(status);
      }).toList();

      if (!mounted || roomSettlements.isEmpty) return;

      final displaySettlements = widget.room.isLeader
          ? [roomSettlements.first]
          : roomSettlements;

      setState(() {
        final settlementMessageIds = displaySettlements
            .map((item) {
              final map = Map<String, dynamic>.from(item as Map);
              return 'settlement_${map['id']}';
            })
            .toSet();

        _messages.removeWhere(
          (message) =>
              message.isSettlement &&
              settlementMessageIds.contains(message.id),
        );

        for (final item in displaySettlements) {
          final map = Map<String, dynamic>.from(item as Map);

          _messages.add(
            _Message(
              id: 'settlement_${map['id']}',
              userId: 'system',
              text: '정산 요청이 도착했습니다.',
              time: TimeOfDay.now().format(context),
              isMe: false,
              isSettlement: true,
              settlement: SettlementMessage.fromJson(map),
            ),
          );
        }
      });

      _scrollToBottomAfterLayout(force: false);
    } catch (e) {
      print('정산 요청 목록 불러오기 실패: $e');
    }
  }

  void _sendMessage() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    // 🌟 서버로 메시지 객체 전송
    _channel?.sink.add(jsonEncode({
      'message': text,
      'sender': widget.myNickname,
    }));

    _inputCtrl.clear();
  }

  @override
  void dispose() {
    NotificationService.currentActiveRoomId = null;
    _channel?.sink.close();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _settlementAmountCtrl.dispose();
    _kakaoPayLinkCtrl.dispose();
    super.dispose();
  }
  // --- 기존 UI 빌더 (_buildChatHeader, _buildInputBar 등) 생략 없이 그대로 유지하여 사용하시면 됩니다 ---
  // (코드 중복 방지를 위해 주요 로직 위주로 재구성하였습니다.)

bool _isNearBottom({double threshold = 120}) {
  if (!_scrollCtrl.hasClients) return true;

  final position = _scrollCtrl.position;
  final distanceFromBottom = position.maxScrollExtent - position.pixels;

  return distanceFromBottom <= threshold;
}

void _scrollToBottom({bool jump = false, bool force = false}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || !_scrollCtrl.hasClients) return;

    if (!force && !_isNearBottom()) return;

    final target = _scrollCtrl.position.maxScrollExtent;

    if (jump) {
      _scrollCtrl.jumpTo(target);
    } else {
      _scrollCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  });
}

void _scrollToBottomAfterLayout({bool jump = false, bool force = false}) {
  _scrollToBottom(jump: jump, force: force);

  Future.delayed(const Duration(milliseconds: 120), () {
    if (!mounted) return;
    _scrollToBottom(jump: jump, force: force);
  });

  Future.delayed(const Duration(milliseconds: 300), () {
    if (!mounted) return;
    _scrollToBottom(jump: jump, force: force);
  });
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F8F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.secondary),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: Color(0xFFF1F1EF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person,
                color: AppColors.gray,
                size: 21,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.room.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.secondary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    '• 참여 중',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: AppColors.secondary),
            onPressed: _showMoreMenu,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildNoticeBar(),

          if (_settlementMessages.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              color: const Color(0xFFF8F8F8),
              child: Column(
                children: _settlementMessages
                    .map((message) => _buildMessageBubble(message))
                    .toList(),
              ),
            ),

          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanDown: (_) {
                FocusScope.of(context).unfocus();
              },
              child: ListView.builder(
                controller: _scrollCtrl,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
                itemCount: _chatMessages.length,
                itemBuilder: (_, i) => _buildMessageBubble(_chatMessages[i]),
              ),
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildSystemMessage(String text) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFEFEFEF),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.gray,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(_Message msg) {
    if (msg.isSettlement && msg.settlement != null) {
      return _buildSettlementRequestCard(msg.settlement!);
    }

    if (msg.isSystem) {
      return _buildSystemMessage(msg.text);
    }

    if (msg.imageFile != null || (msg.imageUrl != null && msg.imageUrl!.isNotEmpty)) {
      return Align(
        alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          constraints: const BoxConstraints(
            maxWidth: 220,
            maxHeight: 220,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: msg.imageFile != null
              ? Image.file(
                  msg.imageFile!,
                  fit: BoxFit.cover,
                )
              : Image.network(
                  msg.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) {
                    return const SizedBox(
                      width: 220,
                      height: 160,
                      child: Center(
                        child: Text(
                          '이미지를 불러올 수 없습니다.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.gray,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      );
    }

    return Align(
      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: const BoxConstraints(maxWidth: 260),
        child: Column(
          crossAxisAlignment:
              msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!msg.isMe)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text(
                  '@${msg.userId}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.gray,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (msg.isMe)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      msg.time,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.gray,
                      ),
                    ),
                  ),

                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: msg.isMe ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: msg.isMe
                          ? null
                          : Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      msg.text,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: msg.isMe ? Colors.white : AppColors.secondary,
                        decoration: msg.isLink
                            ? TextDecoration.underline
                            : TextDecoration.none,
                      ),
                    ),
                  ),
                ),

                if (!msg.isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      msg.time,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.gray,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettlementRequestCard(SettlementMessage settlement) {
    final isCanceled = settlement.isCanceled;
    final isLeader = widget.room.isLeader;
    final isCompleted = _pinnedNotice.contains('정산이 완료되었습니다');

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isCanceled ? const Color(0xFFF3F3F3) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isCanceled ? const Color(0xFFD0D0D0) : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isCanceled ? Icons.block : Icons.receipt_long,
                  color: isCanceled ? AppColors.gray : AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Text(
                  isCompleted
                    ? '정산이 완료되었습니다'
                    : isCanceled
                        ? '취소된 정산 정보입니다'
                        : '정산 요청이 도착했습니다',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isCanceled ? AppColors.gray : AppColors.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isCompleted
                ? '모든 인원의 정산이 완료되어 더 이상 정산을 진행할 수 없습니다.'
                : isCanceled
                    ? '리더가 정산 정보를 수정하여 이 정산 요청은 더 이상 사용할 수 없습니다.'
                    : '총 결제액과 1인당 정산금액을 확인한 뒤 정산을 진행해주세요.',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.gray,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isCanceled || isCompleted
                    ? null
                    : () {
                        if (isLeader) {
                          _showLeaderSettlementCompleteDialog(settlement);
                        } else {
                          _showSettlementDialog(settlement);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isCanceled || isCompleted
                      ? const Color(0xFFD6D6D6)
                      : AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFD6D6D6),
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  isCompleted
                    ? '정산이 완료되었습니다'
                    : isCanceled
                        ? '사용할 수 없는 정산입니다'
                        : isLeader
                            ? '정산 완료하기'
                            : '정산 정보 확인하기',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettlementDialog(SettlementMessage settlement) {
    bool isChecked = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Text(
                '정산 확인',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppColors.secondary,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSettlementInfoRow('총 결제액', settlement.totalAmountText),
                  const SizedBox(height: 8),
                  _buildSettlementInfoRow('1인당 정산금액', settlement.shareAmountText),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _openReceiptImage(settlement.receiptImageUrl),
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('이용내역 확인하기'),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: isChecked,
                        onChanged: (value) {
                          setDialogState(() {
                            isChecked = value ?? false;
                          });
                        },
                      ),
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            '이용내역과 금액을 확인했습니다.\n체크 후 정산하기 버튼이 활성화됩니다.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: AppColors.secondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('닫기'),
                ),
                ElevatedButton(
                  onPressed: isChecked
                    ? () async {
                        try {
                          final result = await SettlementService.openSettlementLink(
                            token: AuthSession.token ?? '',
                            settlementId: settlement.settlementId,
                          );

                          String? link = result['kakaopay_link']?.toString()
                              ?? result['payment_link']?.toString()
                              ?? result['link']?.toString();

                          final paymentChannel = result['payment_channel'];
                          if ((link == null || link.isEmpty) && paymentChannel is Map) {
                            final paymentChannelMap = Map<String, dynamic>.from(paymentChannel);
                            link = paymentChannelMap['kakaopay_link']?.toString()
                                ?? paymentChannelMap['payment_link']?.toString();
                          }

                          link ??= settlement.paymentLink;

                          if (link == null || link.isEmpty) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('등록된 송금 링크가 없습니다.')),
                            );
                            return;
                          }

                          if (mounted) {
                            Navigator.pop(dialogContext);
                          }

                          final uri = Uri.parse(link);
                          final opened = await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );

                          if (!opened && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('송금 링크를 열 수 없습니다.')),
                            );
                          }
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('송금 링크 열림 처리 실패: $e')),
                          );
                        }
                      }
                    : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('정산하기'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showLeaderSettlementCompleteDialog(SettlementMessage settlement) {
    bool isChecked = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Text(
                '정산 완료 확인',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppColors.secondary,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSettlementInfoRow('총 결제액', settlement.totalAmountText),
                  const SizedBox(height: 8),
                  _buildSettlementInfoRow('1인당 정산금액', settlement.shareAmountText),
                  const SizedBox(height: 16),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: isChecked,
                        onChanged: (value) {
                          setDialogState(() {
                            isChecked = value ?? false;
                          });
                        },
                      ),
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            '모든 인원이 정산을 완료하였나요?\n체크 후 정산 완료 버튼이 활성화됩니다.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: AppColors.secondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('닫기'),
                ),
                ElevatedButton(
                  onPressed: isChecked
                    ? () async {
                        Navigator.pop(dialogContext);

                        try {
                          final result = await SettlementService.completeTripSettlement(
                            token: AuthSession.token ?? '',
                            tripId: widget.room.tripId,
                          );

                          final notice = result['pinned_notice']?.toString()
                              ?? '정산이 완료되었습니다.';

                          if (!mounted) return;

                          setState(() {
                            _pinnedNotice = notice;
                          });

                          _channel?.sink.add(
                            jsonEncode({
                              'type': 'settlement_completed',
                              'message': '정산이 완료되었습니다.',
                              'pinned_notice': notice,
                              'expires_at': result['expires_at']?.toString(),
                            }),
                          );

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('정산이 완료되었습니다.'),
                            ),
                          );
                        } catch (e) {
                          if (!mounted) return;

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('정산 완료 처리 실패: $e'),
                            ),
                          );
                        }
                      }
                    : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('정산 완료'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSettlementInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.gray,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.secondary,
          ),
        ),
      ],
    );
  }

  void _openReceiptImage(String? imageUrl) {
    final normalizedImageUrl = _normalizeImageUrl(imageUrl);

    if (normalizedImageUrl == null || normalizedImageUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('등록된 이용내역 이미지가 없습니다.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              InteractiveViewer(
                child: Image.network(
                  normalizedImageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('이미지를 불러올 수 없습니다.'),
                    );
                  },
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNoticeBar() {
    final noticeText = _pinnedNotice.isNotEmpty
      ? _pinnedNotice
      : '택시 번호 및 만날 위치를 꼭 공유해주세요!';

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFEAF5EF),
        border: Border(
          top: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isNoticeExpanded = !_isNoticeExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.push_pin,
                    size: 17,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '공지',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _isNoticeExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 20,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),

          if (_isNoticeExpanded)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                noticeText,
                style: const TextStyle(
                  color: AppColors.secondary,
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  String _seatLabel(String? seatPosition) {
    switch (seatPosition) {
      case 'FRONT_PASSENGER':
        return '앞좌석';
      case 'REAR_LEFT':
        return '뒷좌석 왼쪽';
      case 'REAR_RIGHT':
        return '뒷좌석 오른쪽';
      case 'REAR_MIDDLE':
        return '뒷좌석 가운데';
      default:
        return '-';
    }
  }

  String _roleLabel(String role) {
    return role == 'LEADER' ? '리더' : '참여자';
  }

  Future<void> _showParticipantsDialog() async {
    try {
      final response = await http.get(
        Uri.parse(
          '${AppConfig.apiBaseUrl}/chat/rooms/${widget.room.id}/participants/',
        ),
        headers: {
          'Authorization': 'Token ${AuthSession.token ?? ''}',
        },
      );

      final bodyText = utf8.decode(response.bodyBytes);

      if (response.statusCode != 200) {
        String message = '참여자 목록을 불러오지 못했습니다.';

        try {
          final decodedError = jsonDecode(bodyText);
          if (decodedError is Map && decodedError['detail'] != null) {
            message = decodedError['detail'].toString();
          }
        } catch (_) {}

        throw Exception(message);
      }

      final decoded = jsonDecode(bodyText);

      if (decoded is! Map || decoded['participants'] is! List) {
        throw Exception('참여자 목록 응답 형식이 올바르지 않습니다.');
      }

      final participants = List<Map<String, dynamic>>.from(
        (decoded['participants'] as List).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) {
          return SafeArea(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '참여자 목록',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: AppColors.secondary,
                    ),
                  ),
                  const SizedBox(height: 12),

                  ...participants.map((participant) {
                    final username = participant['username']?.toString() ?? '';
                    final role = participant['role']?.toString() ?? 'MEMBER';
                    final seatPosition =
                        participant['seat_position']?.toString();

                    final isLeader = role == 'LEADER';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9F8F6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isLeader
                                ? Icons.verified_user_outlined
                                : Icons.person_outline,
                            color: isLeader
                                ? AppColors.primary
                                : AppColors.gray,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  username,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.secondary,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${_roleLabel(role)} · 좌석: ${_seatLabel(seatPosition)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.gray,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('닫기'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    }
  }

  Future<void> _leaveChatRoom() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('채팅방 나가기'),
          content: const Text(
            '채팅방을 나가면 해당 매칭에서도 나가게 됩니다. 정말 나가시겠습니까?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                '나가기',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );

    if (shouldLeave != true) return;

    try {
      final response = await http.post(
        Uri.parse(
          '${AppConfig.apiBaseUrl}/chat/rooms/${widget.room.id}/leave/',
        ),
        headers: {
          'Authorization': 'Token ${AuthSession.token ?? ''}',
        },
      );

      final bodyText = utf8.decode(response.bodyBytes);

      if (response.statusCode != 200) {
        String message = '채팅방을 나가지 못했습니다.';

        try {
          final decodedError = jsonDecode(bodyText);
          if (decodedError is Map && decodedError['detail'] != null) {
            message = decodedError['detail'].toString();
          }
        } catch (_) {}

        throw Exception(message);
      }

      _channel?.sink.add(jsonEncode({
        'type': 'system_message', // 백엔드 설정에 맞게 변경 가능 (예: 'trip_updated')
        'message': '${widget.myNickname}님이 채팅방을 나갔습니다.',
      }));
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('채팅방과 매칭에서 나갔습니다.'),
        ),
      );

      TripService.notifyTripsChanged();
      TripService.notifyChatRoomsChanged();

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    }
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDADADA),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                _buildMoreMenuItem(
                  icon: Icons.group_add_outlined,
                  title: '참여자 목록',
                  onTap: () {
                    Navigator.pop(context);
                    _showParticipantsDialog();
                  },
                ),
                const Divider(height: 18),
                _buildMoreMenuItem(
                  icon: Icons.exit_to_app,
                  title: '채팅방 나가기',
                  color: Colors.redAccent,
                  onTap: () {
                    Navigator.pop(context);
                    _leaveChatRoom();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMoreMenuItem({
    required IconData icon,
    required String title,
    Color color = AppColors.secondary,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: color, size: 22),
      title: Text(
        title,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _buildInputBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_showAttachPanel)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildAttachAction(
                      icon: Icons.image_outlined,
                      label: '사진',
                      onTap: () async {
                        setState(() => _showAttachPanel = false);
                        await _pickAndSendImage(ImageSource.gallery);
                      },
                    ),
                    _buildAttachAction(
                      icon: Icons.camera_alt_outlined,
                      label: '카메라',
                      onTap: () async {
                        setState(() => _showAttachPanel = false);
                        await _pickAndSendImage(ImageSource.camera);
                      },
                    ),
                    _buildAttachAction(
                      icon: Icons.receipt_long,
                      label: '정산 요청',
                      onTap: _isSettlementProcessing
                          ? null
                          : () {
                              setState(() => _showAttachPanel = false);
                              _startLeaderSettlementFlow();
                            },
                    ),
                  ],
                ),
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _showAttachPanel = !_showAttachPanel;
                      });
                    },
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: _showAttachPanel
                            ? AppColors.primary
                            : const Color(0xFFF4F4F2),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Icon(
                        _showAttachPanel ? Icons.close : Icons.add,
                        size: 22,
                        color: _showAttachPanel ? Colors.white : AppColors.gray,
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F4F2),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Center(
                        child: TextField(
                          controller: _inputCtrl,
                          maxLines: 1,
                          cursorHeight: 18,
                          textAlignVertical: TextAlignVertical.center,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.2,
                            color: AppColors.secondary,
                          ),
                          decoration: const InputDecoration(
                            hintText: '메시지 입력...',
                            hintStyle: TextStyle(
                              fontSize: 14,
                              height: 1.2,
                              color: Color(0xFF9CA3AF),
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.only(top: 8, bottom: 6),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F4F2),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(
                        Icons.arrow_upward,
                        size: 20,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachAction({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF5EF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.gray,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(source: source);

      if (pickedFile == null) return;

      await _uploadChatImage(File(pickedFile.path));

      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('이미지 전송 실패: $e')),
      );
    }
  }

  Future<void> _startLeaderSettlementFlow() async {
  try {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);

    if (pickedFile == null) {
      return;
    }

    setState(() {
      _isSettlementProcessing = true;
    });

    Future<Map<String, dynamic>> uploadReceipt({required bool resetExisting}) {
      return SettlementService.uploadReceiptImage(
        token: AuthSession.token ?? '',
        tripId: widget.room.tripId,
        imageFile: File(pickedFile.path),
        resetExisting: resetExisting,
      );
    }

    Map<String, dynamic> uploadResult;

    try {
      uploadResult = await uploadReceipt(resetExisting: false);
    } catch (e) {
      final errorText = e.toString();

      if (!errorText.contains('이미 정산이 생성된 영수증입니다')) {
        rethrow;
      }

      if (!mounted) return;

      final shouldReset = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: const Text(
              '정산 정보 수정',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.secondary,
              ),
            ),
            content: const Text(
              '이미 정산 요청이 생성되어 있습니다.\n'
              '기존 정산 정보를 취소하고 새 영수증으로 다시 등록하시겠습니까?',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.secondary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('아니요'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('다시 등록'),
              ),
            ],
          );
        },
      );

      if (shouldReset != true) {
        return;
      }

      uploadResult = await uploadReceipt(resetExisting: true);

      setState(() {
        for (int i = 0; i < _messages.length; i++) {
          final oldSettlement = _messages[i].settlement;

          if (_messages[i].isSettlement && oldSettlement != null) {
            final canceledSettlement = SettlementMessage(
              settlementId: oldSettlement.settlementId,
              totalAmount: oldSettlement.totalAmount,
              shareAmount: oldSettlement.shareAmount,
              receiptImageUrl: oldSettlement.receiptImageUrl,
              paymentLink: oldSettlement.paymentLink,
              status: 'CANCELED',
            );

            _messages[i] = _Message(
              id: _messages[i].id,
              text: '취소된 정산 정보입니다.',
              time: _messages[i].time,
              userId: _messages[i].userId,
              isMe: _messages[i].isMe,
              isLink: _messages[i].isLink,
              isSettlement: true,
              settlement: canceledSettlement,
              imageFile: _messages[i].imageFile,
            );
          }
        }
      });
    }

    final receiptId = _toInt(uploadResult['id']);

      if (receiptId == 0) {
        throw Exception('receipt_id를 찾을 수 없습니다.');
      }

      _currentReceiptId = receiptId;
      _currentReceiptImageUrl = uploadResult['receipt_image_url']?.toString();

      try {
        final ocrResult = await SettlementService.analyzeReceiptOcr(
          token: AuthSession.token ?? '',
          receiptId: receiptId,
        );

        final extractedAmount = _toInt(ocrResult['extracted_total_amount']);

        if (extractedAmount > 0) {
          _settlementAmountCtrl.text = extractedAmount.toString();
        } else {
          _settlementAmountCtrl.clear();
        }
      } catch (e) {
        final errorText = e.toString();

        if (!errorText.contains('수기 정산을 이용해주세요') &&
            !errorText.contains('영수증 이용 시간이 모집 출발 시간과')) {
          rethrow;
        }

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('영수증 시간이 모집 출발 시간과 차이가 큽니다. 수기 정산으로 진행합니다.'),
          ),
        );

        _settlementAmountCtrl.clear();
      }

      try {
        final channel = await SettlementService.getPaymentChannel(
          token: AuthSession.token ?? '',
          tripId: widget.room.tripId,
        );

        final savedLink = channel['kakaopay_link']?.toString() ?? '';
        _kakaoPayLinkCtrl.text = savedLink;
      } catch (e) {
        _kakaoPayLinkCtrl.clear();
        print('송금 링크 불러오기 실패: $e');
      }

      if (!mounted) return;

      _showLeaderSettlementDialog();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('영수증 분석 실패: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSettlementProcessing = false;
        });
      }
    }
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatMessageTime(String? sentAt) {
    if (sentAt == null || sentAt.isEmpty) {
      return TimeOfDay.now().format(context);
    }

    final parsed = DateTime.tryParse(sentAt);

    if (parsed == null) {
      return TimeOfDay.now().format(context);
    }

    final localTime = parsed.toLocal();

    return TimeOfDay(
      hour: localTime.hour,
      minute: localTime.minute,
    ).format(context);
  }

  void _showLeaderSettlementDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            '정산 요청',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: AppColors.secondary,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _settlementAmountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '총 결제 금액',
                  hintText: '예: 18400',
                  hintStyle: TextStyle(color: AppColors.gray),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _kakaoPayLinkCtrl,
                decoration: const InputDecoration(
                  labelText: '카카오페이 송금 링크',
                  hintText: 'https://qr.kakaopay.com/...',
                  hintStyle: TextStyle(color: AppColors.gray),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openReceiptImage(_currentReceiptImageUrl),
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('업로드한 이용내역 확인'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('닫기'),
            ),
            ElevatedButton(
              onPressed: () async {
                await _submitLeaderSettlement(dialogContext);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('정산 요청하기'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _submitLeaderSettlement(BuildContext dialogContext) async {
    final receiptId = _currentReceiptId;
    final amountText = _settlementAmountCtrl.text.replaceAll(',', '').trim();
    final amount = int.tryParse(amountText);
    final link = _kakaoPayLinkCtrl.text.trim();

    if (receiptId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('영수증 정보가 없습니다.')),
      );
      return;
    }

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('올바른 금액을 입력해주세요.')),
      );
      return;
    }

    if (link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('송금 링크를 입력해주세요.')),
      );
      return;
    }

    try {
      await SettlementService.confirmReceiptAmount(
        token: AuthSession.token ?? '',
        receiptId: receiptId,
        totalAmount: amount,
      );

      await SettlementService.upsertPaymentChannel(
        token: AuthSession.token ?? '',
        tripId: widget.room.tripId,
        kakaopayLink: link,
      );

      final settlements = await SettlementService.createSettlements(
        token: AuthSession.token ?? '',
        tripId: widget.room.tripId,
      );

      if (!mounted) return;

      Navigator.pop(dialogContext);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('정산 요청이 생성되었습니다.')),
      );

      if (settlements.isNotEmpty) {
        final first = Map<String, dynamic>.from(settlements.first as Map);

        _channel?.sink.add(jsonEncode({
          'type': 'settlement_request',
          'message': '정산 요청이 도착했습니다.',
          'settlement': first,
        }));
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('정산 요청 실패: $e')),
      );
    }
  }
  }