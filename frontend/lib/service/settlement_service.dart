import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class SettlementService {
  static String get serverUrl => AppConfig.apiBaseUrl;

  static Map<String, String> _headers(String token) {
    return {
      'Authorization': 'Token $token',
      'Content-Type': 'application/json',
    };
  }

  /// 참여자가 내야 할 정산 목록 조회
  /// GET /api/settlements/me/settlements/pay/
  static Future<List<dynamic>> getMyPaySettlements({
    required String token,
  }) async {
    final uri = Uri.parse('$serverUrl/api/settlements/me/settlements/pay/');

    final response = await http.get(
      uri,
      headers: _headers(token),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));

      if (decoded is List) {
        return decoded;
      }

      if (decoded is Map<String, dynamic> && decoded['results'] is List) {
        return decoded['results'] as List<dynamic>;
      }

      return [];
    }

    throw Exception(
      '정산 목록 조회 실패: ${response.statusCode} ${response.body}',
    );
  }

  /// 특정 trip의 정산 목록 조회
  /// GET /api/settlements/trips/<trip_id>/settlements/
  static Future<List<dynamic>> getTripSettlements({
    required String token,
    required int tripId,
  }) async {
    final uri = Uri.parse(
      '$serverUrl/api/settlements/trips/$tripId/settlements/',
    );

    final response = await http.get(
      uri,
      headers: _headers(token),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));

      if (decoded is List) {
        return decoded;
      }

      if (decoded is Map<String, dynamic> && decoded['results'] is List) {
        return decoded['results'] as List<dynamic>;
      }

      return [];
    }

    throw Exception(
      'Trip 정산 목록 조회 실패: ${response.statusCode} ${response.body}',
    );
  }

  /// 리더가 trip 정산을 최종 완료 처리
  /// POST /api/settlements/trips/<trip_id>/settlements/complete/
  static Future<Map<String, dynamic>> completeTripSettlement({
    required String token,
    required int tripId,
  }) async {
    final uri = Uri.parse(
      '$serverUrl/api/settlements/trips/$tripId/settlements/complete/',
    );

    final response = await http.post(
      uri,
      headers: _headers(token),
    );

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));

    if (response.statusCode == 200 && decoded is Map<String, dynamic>) {
      return decoded;
    }

    throw Exception(
      'Trip 정산 완료 처리 실패: ${response.statusCode} ${response.body}',
    );
  }

  /// 정산 상세 조회
  /// GET /api/settlements/settlements/<settlement_id>/
  static Future<Map<String, dynamic>> getSettlementDetail({
    required String token,
    required int settlementId,
  }) async {
    final uri = Uri.parse(
      '$serverUrl/api/settlements/settlements/$settlementId/',
    );

    final response = await http.get(
      uri,
      headers: _headers(token),
    );

    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    }

    throw Exception(
      '정산 상세 조회 실패: ${response.statusCode} ${response.body}',
    );
  }

  /// 참여자가 체크박스 확인 후 송금 링크 열기
  /// POST /api/settlements/settlements/<settlement_id>/open-link/
  static Future<Map<String, dynamic>> openSettlementLink({
    required String token,
    required int settlementId,
  }) async {
    final uri = Uri.parse(
      '$serverUrl/api/settlements/settlements/$settlementId/open-link/',
    );

    final response = await http.post(
      uri,
      headers: _headers(token),
    );

    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    }

    throw Exception(
      '송금 링크 열림 처리 실패: ${response.statusCode} ${response.body}',
    );
  }

  /// 참여자가 송금 완료 처리
  /// POST /api/settlements/settlements/<settlement_id>/pay-self/
  static Future<Map<String, dynamic>> markPaidSelf({
    required String token,
    required int settlementId,
  }) async {
    final uri = Uri.parse(
      '$serverUrl/api/settlements/settlements/$settlementId/pay-self/',
    );

    final response = await http.post(
      uri,
      headers: _headers(token),
    );

    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    }
  
    throw Exception(
      '송금 완료 처리 실패: ${response.statusCode} ${response.body}',
    );
  }

    /// 리더가 영수증/이용내역 이미지 업로드
  /// POST /api/settlements/trips/<trip_id>/receipt/
  static Future<Map<String, dynamic>> uploadReceiptImage({
    required String token,
    required int tripId,
    required File imageFile,
    bool resetExisting = false,
  }) async {
    final uri = Uri.parse(
      '$serverUrl/api/settlements/trips/$tripId/receipt/',
    );

    final request = http.MultipartRequest('POST', uri);

    request.headers['Authorization'] = 'Token $token';
    request.fields['reset_existing'] = resetExisting ? 'true' : 'false';

    request.files.add(
      await http.MultipartFile.fromPath(
        'image',
        imageFile.path,
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 201 || response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    }

    throw Exception(
      '영수증 업로드 실패: ${response.statusCode} ${response.body}',
    );
  }

  /// 리더가 업로드한 영수증 OCR 분석 실행
  /// POST /api/settlements/receipts/<receipt_id>/analyze/
  static Future<Map<String, dynamic>> analyzeReceiptOcr({
    required String token,
    required int receiptId,
  }) async {
    final uri = Uri.parse(
      '$serverUrl/api/settlements/receipts/$receiptId/analyze/',
    );

    final response = await http.post(
      uri,
      headers: _headers(token),
    );

    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    }

    throw Exception(
      'OCR 분석 실패: ${response.statusCode} ${response.body}',
    );
  }

  /// 리더가 OCR 추출 금액 또는 수정 금액을 최종 확정
  /// PATCH /api/settlements/receipts/<receipt_id>/confirm-amount/
  static Future<Map<String, dynamic>> confirmReceiptAmount({
    required String token,
    required int receiptId,
    required int totalAmount,
  }) async {
    final uri = Uri.parse(
      '$serverUrl/api/settlements/receipts/$receiptId/confirm-amount/',
    );

    final response = await http.patch(
      uri,
      headers: _headers(token),
      body: jsonEncode({
        'total_amount': totalAmount,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    }

    throw Exception(
      '최종 금액 확정 실패: ${response.statusCode} ${response.body}',
    );
  }

  /// 리더가 카카오페이/토스 등 송금 링크 등록
  /// POST /api/settlements/trips/<trip_id>/payment-channel/
  static Future<Map<String, dynamic>> upsertPaymentChannel({
    required String token,
    required int tripId,
    String provider = 'KAKAOPAY',
    required String kakaopayLink,
  }) async {
    final uri = Uri.parse(
      '$serverUrl/api/settlements/trips/$tripId/payment-channel/',
    );

    final response = await http.post(
      uri,
      headers: _headers(token),
      body: jsonEncode({
        'provider': provider,
        'kakaopay_link': kakaopayLink,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    }

    throw Exception(
      '송금 링크 등록 실패: ${response.statusCode} ${response.body}',
    );
  }

  static Future<Map<String, dynamic>> getPaymentChannel({
    required String token,
    required int tripId,
  }) async {
    final uri = Uri.parse(
      '$serverUrl/api/settlements/trips/$tripId/payment-channel/detail/',
    );

    final response = await http.get(
      uri,
      headers: _headers(token),
    );

    final data = jsonDecode(utf8.decode(response.bodyBytes));

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(data);
    }

    throw Exception(data['detail'] ?? data['message'] ?? data.toString());
    }

  /// 리더가 참여자별 정산 요청 생성
  /// POST /api/settlements/trips/<trip_id>/settlements/create/
  static Future<List<dynamic>> createSettlements({
    required String token,
    required int tripId,
  }) async {
    final uri = Uri.parse(
      '$serverUrl/api/settlements/trips/$tripId/settlements/create/',
    );

    final response = await http.post(
      uri,
      headers: _headers(token),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));

      if (decoded is List) {
        return decoded;
      }

      if (decoded is Map<String, dynamic> && decoded['results'] is List) {
        return decoded['results'] as List<dynamic>;
      }

      return [];
    }

    throw Exception(
      '정산 요청 생성 실패: ${response.statusCode} ${response.body}',
    );
  }
}