import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../service/settlement_service.dart';
import '../../utils/colors.dart';

class SettlementTab extends StatefulWidget {
  const SettlementTab({super.key});

  @override
  State<SettlementTab> createState() => _SettlementTabState();
}

class _SettlementTabState extends State<SettlementTab> {
  bool _isLoading = true;
  List<dynamic> _settlements = [];

  // TODO: 나중에는 로그인 후 저장된 실제 token을 가져와야 함.
  // 지금은 Postman에서 사용했던 "참여자 token"을 임시로 넣어서 테스트.
  static const String _token = '여기에_참여자_TOKEN_넣기';

  @override
  void initState() {
    super.initState();
    _fetchSettlements();
  }

  Future<void> _fetchSettlements() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final data = await SettlementService.getMyPaySettlements(token: _token);

      if (!mounted) return;

      setState(() {
        _settlements = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('정산 목록을 불러오지 못했습니다: $e')),
      );
    }
  }

  Future<void> _openSettlementModal(int settlementId) async {
    try {
      final detail = await SettlementService.getSettlementDetail(
        token: _token,
        settlementId: settlementId,
      );

      if (!mounted) return;

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(24),
          ),
        ),
        builder: (_) {
          return SettlementConfirmSheet(
            token: _token,
            settlement: detail,
            onUpdated: _fetchSettlements,
          );
        },
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('정산 상세를 불러오지 못했습니다: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _fetchSettlements,
                      child: _settlements.isEmpty
                          ? ListView(
                              children: const [
                                SizedBox(height: 160),
                                Center(
                                  child: Text(
                                    '아직 정산할 내역이 없습니다.',
                                    style: TextStyle(
                                      color: AppColors.gray,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _settlements.length,
                              itemBuilder: (_, index) {
                                final item = _settlements[index];

                                if (item is! Map<String, dynamic>) {
                                  return const SizedBox.shrink();
                                }

                                return _buildSettlementCard(item);
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: const Text(
        '정산',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          color: AppColors.secondary,
        ),
      ),
    );
  }

  Widget _buildSettlementCard(Map<String, dynamic> item) {
    final int settlementId = item['id'] ?? 0;
    final int tripId = item['trip_id'] ?? 0;
    final int shareAmount = item['share_amount'] ?? 0;
    final int totalAmount = item['total_amount'] ?? 0;
    final String status = item['status']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long,
                color: AppColors.primary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Trip #$tripId 정산 요청',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.secondary,
                  ),
                ),
              ),
              _statusChip(status),
            ],
          ),
          const SizedBox(height: 16),
          _amountRow('총 결제금액', totalAmount),
          const SizedBox(height: 8),
          _amountRow('내 정산금액', shareAmount, isStrong: true),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: status == 'CONFIRMED'
                  ? null
                  : () => _openSettlementModal(settlementId),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.border,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                status == 'CONFIRMED' ? '정산 완료' : '정산하기',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountRow(String label, int amount, {bool isStrong = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.gray,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          '${_formatMoney(amount)}원',
          style: TextStyle(
            color: isStrong ? AppColors.primary : AppColors.secondary,
            fontSize: isStrong ? 18 : 15,
            fontWeight: isStrong ? FontWeight.w900 : FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _statusChip(String status) {
    final label = _statusLabel(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppColors.secondary,
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'REQUEST':
        return '요청됨';
      case 'LINK_OPENED':
        return '링크 열림';
      case 'PAID_SELF':
        return '송금 완료';
      case 'CONFIRMED':
        return '확인 완료';
      case 'DISPUTED':
        return '이의제기';
      case 'CANCELED':
        return '취소됨';
      default:
        return status;
    }
  }

  String _formatMoney(int value) {
    return value.toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (_) => ',',
        );
  }
}

class SettlementConfirmSheet extends StatefulWidget {
  final String token;
  final Map<String, dynamic> settlement;
  final VoidCallback onUpdated;

  const SettlementConfirmSheet({
    super.key,
    required this.token,
    required this.settlement,
    required this.onUpdated,
  });

  @override
  State<SettlementConfirmSheet> createState() => _SettlementConfirmSheetState();
}

class _SettlementConfirmSheetState extends State<SettlementConfirmSheet> {
  bool _checked = false;
  bool _isSubmitting = false;

  int get settlementId => widget.settlement['id'] ?? 0;

  int get totalAmount => widget.settlement['total_amount'] ?? 0;

  int get shareAmount => widget.settlement['share_amount'] ?? 0;

  String get receiptImageUrl =>
      widget.settlement['receipt_image_url']?.toString() ?? '';

  String get kakaopayLink {
    final channel = widget.settlement['payment_channel'];

    if (channel is Map<String, dynamic>) {
      return channel['kakaopay_link']?.toString() ?? '';
    }

    return '';
  }

  Future<void> _showReceiptImage() async {
    if (receiptImageUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('확인할 이용내역 이미지가 없습니다.')),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReceiptImageViewer(imageUrl: receiptImageUrl),
      ),
    );
  }

  Future<void> _openPaymentLink() async {
    if (!_checked) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final updated = await SettlementService.openSettlementLink(
        token: widget.token,
        settlementId: settlementId,
      );

      final channel = updated['payment_channel'];
      final link = channel is Map<String, dynamic>
          ? channel['kakaopay_link']?.toString() ?? kakaopayLink
          : kakaopayLink;

      if (link.isEmpty) {
        throw Exception('송금 링크가 없습니다.');
      }

      final uri = Uri.parse(link);

      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!mounted) return;

      widget.onUpdated();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('송금 링크를 열었습니다. 송금 후 완료 버튼을 눌러주세요.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('송금 링크를 열지 못했습니다: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _markPaidSelf() async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      await SettlementService.markPaidSelf(
        token: widget.token,
        settlementId: settlementId,
      );

      if (!mounted) return;

      widget.onUpdated();
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('송금 완료로 처리했습니다.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('송금 완료 처리 실패: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '정산 확인',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: AppColors.secondary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _infoBox(),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _showReceiptImage,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('이용내역 확인하기'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.secondary,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _checked,
                onChanged: (value) {
                  setState(() {
                    _checked = value ?? false;
                  });
                },
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  '이용내역과 금액을 확인했습니다',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.secondary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: !_checked || _isSubmitting ? null : _openPaymentLink,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.border,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '정산하기',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isSubmitting ? null : _markPaidSelf,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.secondary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    '송금 완료',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoBox() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _row('총 결제금액', totalAmount),
          const SizedBox(height: 10),
          _row('1인당 정산금액', shareAmount, strong: true),
        ],
      ),
    );
  }

  Widget _row(String label, int amount, {bool strong = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.gray,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          '${_formatMoney(amount)}원',
          style: TextStyle(
            color: strong ? AppColors.primary : AppColors.secondary,
            fontSize: strong ? 19 : 15,
            fontWeight: strong ? FontWeight.w900 : FontWeight.w800,
          ),
        ),
      ],
    );
  }

  String _formatMoney(int value) {
    return value.toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (_) => ',',
        );
  }
}

class ReceiptImageViewer extends StatelessWidget {
  final String imageUrl;

  const ReceiptImageViewer({
    super.key,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('이용내역 확인'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4.0,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) {
              return const Text(
                '이미지를 불러올 수 없습니다.',
                style: TextStyle(color: Colors.white),
              );
            },
          ),
        ),
      ),
    );
  }
}