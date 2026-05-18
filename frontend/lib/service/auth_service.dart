import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'auth_session.dart';

class AuthService {

  // 에뮬레이터 기준 localhost 주소. 실기기 테스트 시 192.168.x.x (PC의 IP)로 변경해야 합니다.
  static String get baseUrl => '${AppConfig.apiBaseUrl}/api/accounts';
  // ============================================================
  // [실제 통신] 백엔드(Django)와 연결된 API
  // ============================================================

  static String _signupErrorMessage(Map<String, dynamic> data) {
    final raw = data['message'] ?? data;

    final text = raw.toString();

    final hasUsernameError =
        text.contains('username') ||
        text.contains('user with this username already exists');

    final hasPhoneError =
        text.contains('phone_number') ||
        text.contains('user with this phone number already exists');

    if (hasUsernameError && hasPhoneError) {
      return '이미 사용 중인 아이디와 전화번호입니다.';
    }

    if (hasUsernameError) {
      return '이미 사용 중인 아이디입니다.';
    }

    if (hasPhoneError) {
      return '이미 사용 중인 전화번호입니다.';
    }

    if (text.contains('password')) {
      return '비밀번호 형식을 확인해주세요.';
    }

    return data['message']?.toString() ?? '회원가입에 실패했습니다.';
  }

  // 1. 옥토모 역발상 인증 - 6자리 코드 발급 API
  static Future<Map<String, dynamic>> sendVerificationCode({required String phone}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/send-code/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return {
          'success': true,
          'code': data['code'],
          'octomoNumber': data['octomoNumber'] ?? '1666-3538',
          'message': data['message'],
        };
      }
      
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return {'success': false, 'message': data['message'] ?? '코드 발급 실패'};
    } catch (e) {
      return {'success': false, 'message': '서버 연결 오류가 발생했습니다. 네트워크 상태를 확인해주세요.'};
    }
  }

  // 2. 옥토모 역발상 인증 - SMS 발송 여부 확인 API
  static Future<Map<String, dynamic>> verifyCode({required String phone}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/verify-code/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      );
      
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      
      if (response.statusCode == 200 && data['verified'] == true) {
        return {'success': true, 'verified': true, 'message': data['message'] ?? '인증 완료'};
      }
      
      return {
        'success': false,
        'verified': false,
        'message': data['message'] ?? '인증 확인 실패'
      };
    } catch (e) {
      return {'success': false, 'verified': false, 'message': '서버 연결 오류가 발생했습니다. 네트워크 상태를 확인해주세요.'};
    }
  }

  // 3. 회원가입 API
  static Future<Map<String, dynamic>> signup({
    required String name,
    required String username, // UI의 '아이디'
    required String gender,
    required String phone,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/signup/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'user_real_name': name,
          'password': password,
          'phone_number': phone,
          'gender': gender == '남' ? 'M' : 'F',
        }),
      );

      final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));

      if ((response.statusCode == 201 || response.statusCode == 200) &&
          data['success'] == true) {
        return {
          'success': true,
          'message': data['message'] ?? '회원가입 성공',
        };
      }

      return {
        'success': false,
        'message': _signupErrorMessage(data),
      };
    } catch (e) {
      return {'success': false, 'message': '서버 연결 오류가 발생했습니다. 네트워크 상태를 확인해주세요.'};
    }
  }

  // 4. 로그인 API
  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200) {
        return {
          'success': true,
          'token': data['token'],
          'username': data['username'],
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? '아이디 또는 비밀번호가 틀립니다.'
        };
      }
    } catch (e) {
      return {'success': false, 'message': '서버 연결 오류가 발생했습니다. 네트워크 상태를 확인해주세요.'};
    }
  }

  // ============================================================
  // [가짜 데이터] UI 테스트용 임시 함수 (백엔드 완성 시 http 로직으로 교체)
  // ============================================================

  // 5. 로그아웃
  static Future<Map<String, dynamic>> logout() async {
    try {
      final token = AuthSession.token;

      if (token == null || token.isEmpty) {
        AuthSession.clear();
        return {
          'success': true,
          'message': '이미 로그아웃 상태입니다.',
        };
      }

      final response = await http.post(
        Uri.parse('$baseUrl/logout/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Token $token',
        },
      );

      AuthSession.clear();

      if (response.statusCode == 200) {
        final data = response.body.isNotEmpty
            ? jsonDecode(utf8.decode(response.bodyBytes))
            : <String, dynamic>{};

        return {
          'success': true,
          'message': data['message'] ?? '로그아웃 되었습니다.',
        };
      }

      return {
        'success': true,
        'message': '기기에서 로그아웃 되었습니다.',
      };
    } catch (e) {
      AuthSession.clear();
      return {
        'success': true,
        'message': '오프라인 상태로 로그아웃 되었습니다.',
      };
    }
  }

  // 6. 프로필 이미지 업데이트
  static Future<void> updateProfile({required String profileImgUrl}) async {
    await Future.delayed(const Duration(seconds: 1));
  }

  static Future<Map<String, dynamic>> updateProfileImage(File imageFile) async {
    try {
      final token = AuthSession.token;

      if (token == null || token.isEmpty) {
        return {
          'success': false,
          'message': '로그인이 필요합니다.',
        };
      }

      final uri = Uri.parse('$baseUrl/profile/image/');
      final request = http.MultipartRequest('POST', uri);

      request.headers['Authorization'] = 'Token $token';

      request.files.add(
        await http.MultipartFile.fromPath('profile_image', imageFile.path),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      final data = response.body.isNotEmpty
          ? jsonDecode(utf8.decode(response.bodyBytes))
          : <String, dynamic>{};

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message': data['message'] ?? '프로필 이미지가 변경되었습니다.',
          'profile_img_url': data['profile_img_url'],
        };
      }

      return {
        'success': false,
        'message': data['error'] ?? data['message'] ?? '이미지 업로드에 실패했습니다. (${response.statusCode})',
      };
    } catch (e) {
      return {
        'success': false,
        'message': '서버 연결 오류가 발생했습니다. 네트워크 상태를 확인해주세요.',
      };
    }
  }

  // 7. 회원 탈퇴 (myPage_tab.dart 호출에 맞춤)
  static Future<Map<String, dynamic>> withdraw({required String reason}) async {
    try {
      final token = AuthSession.token;

      if (token == null || token.isEmpty) {
        return {
          'is_blocked': false,
          'success': false,
          'message': '로그인이 필요합니다.',
        };
      }

      final url = Uri.parse('$baseUrl/withdraw/');

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'reason': reason,
        }),
      );

      final data = response.body.isNotEmpty
          ? jsonDecode(utf8.decode(response.bodyBytes))
          : <String, dynamic>{};

      if (response.statusCode == 200 || response.statusCode == 201) {
        AuthSession.clear();

        return {
          'success': true,
          'is_blocked': data['is_blocked'] ?? false,
          'message': data['message'] ?? '탈퇴 처리가 완료되었습니다.',
        };
      }

      return {
        'success': false,
        'is_blocked': false,
        'message': data['message'] ?? '탈퇴 처리에 실패했습니다. (${response.statusCode})',
      };
    } catch (e) {
      return {
        'success': false,
        'is_blocked': false,
        'message': '서버 연결 오류가 발생했습니다. 네트워크 상태를 확인해주세요.',
      };
    }
  }

  // 8. 유저 신고 (myPage_tab.dart 호출 파라미터 4개에 맞춤)
  static Future<Map<String, dynamic>> reportUser({
    required String targetId,
    required String tripId,
    required String reason,
    String? detail,
  }) async {
    try {
      final token = AuthSession.token;

      if (token == null || token.isEmpty) {
        return {
          'success': false,
          'message': '로그인이 필요합니다.',
        };
      }

      final url = Uri.parse('${AppConfig.apiBaseUrl}/api/moderation/report/');

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'target_id': targetId,
          'trip_id': tripId,
          'reason': reason,
          'detail': detail ?? '',
        }),
      );

      final data = response.body.isNotEmpty
          ? jsonDecode(utf8.decode(response.bodyBytes))
          : <String, dynamic>{};

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message': data['message'] ?? '신고가 성공적으로 접수되었습니다.',
        };
      }

      return {
        'success': false,
        'message': data['message'] ?? '신고 접수에 실패했습니다. (${response.statusCode})',
      };
    } catch (e) {
      return {
        'success': false,
        'message': '서버 연결 오류가 발생했습니다. 네트워크 상태를 확인해주세요.',
      };
    }
  }

  // 9. 이용 내역 데이터 반환 (List<Map> 타입으로 에러 방지)
  static Future<List<Map<String, dynamic>>> getTripHistory() async {
    try {
      final token = AuthSession.token;

      if (token == null || token.isEmpty) {
        throw Exception('로그인이 필요합니다.');
      }

      final url = Uri.parse('$baseUrl/history/');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));

        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }

        return [];
      }

      throw Exception('이용 내역을 불러오지 못했습니다. (${response.statusCode})');
    } catch (e) {
      throw Exception('이용 내역을 불러오는 데 실패했습니다: $e');
    }
  }

  // 10. 매너 로그 데이터 반환
  static Future<List<Map<String, dynamic>>> getTrustScoreLogs() async {
    try {
      final token = AuthSession.token;

      if (token == null || token.isEmpty) {
        throw Exception('로그인이 필요합니다.');
      }

      final url = Uri.parse('${AppConfig.apiBaseUrl}/api/moderation/trust-score-logs/');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));

        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }

        return [];
      }

      throw Exception('매너 로그를 불러오지 못했습니다. (${response.statusCode})');
    } catch (e) {
      throw Exception('매너 로그를 불러오는 데 실패했습니다: $e');
    }
  }

  // 11. 신고 가능한 여정 및 동승자 목록 반환
  static Future<List<Map<String, dynamic>>> getRecentCompanions() async {
    try {
      final token = AuthSession.token;

      if (token == null || token.isEmpty) {
        throw Exception('로그인이 필요합니다.');
      }

      final url = Uri.parse('$baseUrl/recent-companions/');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));

        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }

        return [];
      }

      throw Exception('신고 가능한 여정 목록을 불러오지 못했습니다. (${response.statusCode})');
    } catch (e) {
      throw Exception('신고 가능한 여정 목록을 불러오는 데 실패했습니다: $e');
    }
  }

  static Future<Map<String, dynamic>> updateLoggedUserPhone({
    required String phone,
  }) async {
    try {
      final token = AuthSession.token;

      if (token == null || token.isEmpty) {
        return {
          'success': false,
          'message': '로그인이 필요합니다.',
        };
      }

      final url = Uri.parse('$baseUrl/update-phone/');

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'phone': phone,
        }),
      );

      final data = response.body.isNotEmpty
          ? jsonDecode(utf8.decode(response.bodyBytes))
          : <String, dynamic>{};

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': data['success'] ?? true,
          'message': data['message'] ?? '전화번호 인증 및 변경이 완료되었습니다.',
          'phone': data['phone'],
        };
      }

      return {
        'success': false,
        'message': data['message'] ?? '전화번호 변경에 실패했습니다. (${response.statusCode})',
      };
    } catch (e) {
      return {
        'success': false,
        'message': '서버 연결 오류가 발생했습니다. 네트워크 상태를 확인해주세요.',
      };
    }
  }


    static Future<Map<String, dynamic>> getProfile() async {
    try {
      final token = AuthSession.token;

      if (token == null || token.isEmpty) {
        return {
          'success': false,
          'message': '로그인이 필요합니다.',
        };
      }

      final response = await http.get(
        Uri.parse('$baseUrl/profile/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Token $token',
        },
      );

      final data = response.body.isNotEmpty
          ? jsonDecode(utf8.decode(response.bodyBytes))
          : <String, dynamic>{};

      if (response.statusCode == 200 && data is Map<String, dynamic>) {
        return data;
      }

      return {
        'success': false,
        'message': data is Map<String, dynamic>
            ? data['message'] ?? '프로필 로딩 실패'
            : '프로필 로딩 실패',
      };
    } catch (e) {
      return {
        'success': false,
        'message': '서버 연결 오류',
      };
    }
  }
}
