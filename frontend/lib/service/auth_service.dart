import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'auth_session.dart';
import 'dart:io';
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
        AuthSession.save(
                  newToken: data['token'],
                  newUsername: data['username']
                );
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
        final token = AuthSession.token; // 현재 로그인된 토큰 가져오기

        // 이미 토큰이 없다면 로그아웃된 것으로 간주
        if (token == null) {
          return {'success': true, 'message': '이미 로그아웃 상태입니다.'};
        }

        // 백엔드에 토큰 삭제 요청
        final response = await http.post(
          Uri.parse('$baseUrl/logout/'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Token $token', // 토큰을 헤더에 담아 전송
          },
        );

        // 서버 로직 성공 여부와 관계없이, 앱 내의 세션은 비워주는 것이 안전합니다.
        // (AuthSession 파일에 저장된 값을 비우는 함수를 호출하세요. 이름은 다를 수 있습니다.)
        AuthSession.clear(); // 예: SharedPreferences에서 토큰 삭제 등

        if (response.statusCode == 200) {
          return {'success': true, 'message': '로그아웃 되었습니다.'};
        } else {
          // 서버에서 토큰을 찾지 못해 에러가 나더라도, 로컬 기기에서는 로그아웃 처리함
          return {'success': true, 'message': '기기에서 로그아웃 되었습니다.'};
        }
      } catch (e) {
        // 네트워크 오류 시에도 기기 로컬 데이터는 지워주어 로그아웃 상태를 만들어 줍니다.
        AuthSession.clear();
        return {'success': true, 'message': '오프라인 상태로 로그아웃 되었습니다.'};
      }
    }

  // 6. 프로필 이미지 업데이트


    // 6. 프로필 이미지 업데이트 API (채팅방 파일 전송 방식 적용)
    static Future<Map<String, dynamic>> updateProfileImage(File imageFile) async {
      try {
        final token = AuthSession.token;
        if (token == null) {
          return {'success': false, 'message': '로그인이 필요합니다.'};
        }

        // 백엔드의 ProfileImageUpdateView에 연결되는 URL (urls.py 설정에 맞춰 주소 확인 필요)
        final uri = Uri.parse('$baseUrl/profile/image/');

        final request = http.MultipartRequest('POST', uri);

        // 헤더에 토큰 추가
        request.headers['Authorization'] = 'Token $token';

        // 백엔드(views.py)에서 request.FILES['profile_image'] 로 찾고 있으므로
        // 필드명을 'profile_image'로 정확히 맞춥니다.
        request.files.add(
          await http.MultipartFile.fromPath('profile_image', imageFile.path),
        );

        // 서버로 전송
        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200 || response.statusCode == 201) {
          return {'success': true, 'message': '프로필 이미지가 성공적으로 변경되었습니다.'};
        } else {
          return {'success': false, 'message': '이미지 업로드에 실패했습니다. (${response.statusCode})'};
        }
      } catch (e) {
        return {'success': false, 'message': '네트워크 오류가 발생했습니다: $e'};
      }
    }

  // 7. 회원 탈퇴 (myPage_tab.dart 호출에 맞춤)
  static Future<Map<String, dynamic>> withdraw({required String reason}) async {
      try {
        final token = AuthSession.token;
        if (token == null) {
          return {'is_blocked': false, 'message': '로그인이 필요합니다.'};
        }

        // 백엔드의 WithdrawView와 연결된 URL
        // (백엔드 urls.py에 'withdraw/' 로 연결되어 있다고 가정)
        final url = Uri.parse('$baseUrl/withdraw/');

        final response = await http.post(
          url,
          headers: {
            'Authorization': 'Token $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'reason': reason, // 사용자가 입력/선택한 탈퇴 사유 전송
          }),
        );

        // 성공 시 (200 OK)
        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes));

          // 🚨 탈퇴에 성공했으므로 기기 로컬에 저장된 토큰(로그인 정보)을 비워야 합니다!
          // AuthSession 클래스에 구현해두신 초기화 함수를 호출하세요 (예: clear, logout 등)
          AuthSession.clear();

          return {
            'is_blocked': data['is_blocked'] ?? false,
            'message': data['message'] ?? '탈퇴 처리가 완료되었습니다.',
          };
        } else {
          // 실패 시
          return {
            'is_blocked': false,
            'message': '탈퇴 처리에 실패했습니다. (상태 코드: ${response.statusCode})'
          };
        }
      } catch (e) {
        return {
          'is_blocked': false,
          'message': '서버 연결 오류가 발생했습니다. 네트워크 상태를 확인해주세요.'
        };
      }
    }

    // 8. 유저 신고 (실제 API 연동 완료)
    static Future<Map<String, dynamic>> reportUser({
      required String targetId,
      required String tripId,
      required String reason,
      String? detail,
    }) async {
      try {
        final token = AuthSession.token;
        if (token == null) return {'success': false, 'message': '로그인이 필요합니다.'};

        // 🚨 주의: 백엔드 urls.py 설정에 따라 주소가 다를 수 있습니다.
        // 만약 이전 매너 로그(getTrustScoreLogs)처럼 moderation 앱 소속이라면
        // Uri.parse('${AppConfig.apiBaseUrl}/api/moderation/report/') 로 바꿔주세요!
        final url = Uri.parse('$baseUrl/report/');

        final response = await http.post(
          url,
          headers: {
            'Authorization': 'Token $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'target_id': targetId, // 백엔드 request.data.get('target_id')와 매칭
            'trip_id': tripId,     // 백엔드 request.data.get('trip_id')와 매칭
            'reason': reason,      // 백엔드 request.data.get('reason')과 매칭
            'detail': detail ?? '',// 백엔드 request.data.get('detail')과 매칭
          }),
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          // 성공 시 백엔드에서 보낸 {"message": "Report submitted successfully"} 를 받을 수 있습니다.
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          return {
            'success': true,
            'message': '신고가 성공적으로 접수되었습니다.'
          };
        } else {
          return {
            'success': false,
            'message': '신고 접수에 실패했습니다. (상태 코드: ${response.statusCode})'
          };
        }
      } catch (e) {
        return {
          'success': false,
          'message': '서버 연결 오류가 발생했습니다. 네트워크 상태를 확인해주세요.'
        };
      }
    }

  // 9. 이용 내역 데이터 반환 (List<Map> 타입으로 에러 방지)
  static Future<List<Map<String, dynamic>>> getTripHistory() async {
    final url = Uri.parse('$baseUrl/history/');

        final response = await http.get(
          url,
          headers: {
            'Authorization': 'Token ${AuthSession.token}', // 로그인 토큰
            'Content-Type': 'application/json',
          },
        );

        if (response.statusCode == 200) {
          // 한글 깨짐 방지를 위해 utf8.decode 사용
          final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
          return data.map((item) => item as Map<String, dynamic>).toList();
        } else {
          throw Exception('이용 내역 조회 실패: ${response.statusCode}');
        }
      }
  static Future<List<Map<String, dynamic>>> getTrustScoreLogs() async {
    final url = Uri.parse('${AppConfig.apiBaseUrl}/api/moderation/trust-score-logs/');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Token ${AuthSession.token}',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {

      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.map((item) => item as Map<String, dynamic>).toList();
    } else {
      throw Exception('매너 로그 조회 실패: ${response.statusCode}');
    }
  }

  // 11. 최근 동승자 데이터 반환
  static Future<List<Map<String, dynamic>>> getRecentCompanions() async {
      final token = AuthSession.token;
      if (token == null) {
        throw Exception('로그인이 필요합니다.');
      }

      // 백엔드의 RecentCompanionsView와 연결된 URL
      // (백엔드 urls.py 설정에 따라 /recent-companions/ 가 아닐 수 있으니 주소 확인 필요!)
      final url = Uri.parse('$baseUrl/recent-companions/');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        // 서버에서 보낸 JSON을 List로 변환
        final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        return data.map((item) => item as Map<String, dynamic>).toList();
      } else {
        throw Exception('동승자 내역 조회 실패: ${response.statusCode}');
      }
    }
    static Future<Map<String, dynamic>> getProfile() async {
        try {
          final token = AuthSession.token; // 저장된 토큰 가져오기
          if (token == null) return {'success': false, 'message': '로그인이 필요합니다.'};

          final response = await http.get(
            Uri.parse('$baseUrl/profile/'), // 백엔드 프로필 엔드포인트
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Token $token', // 토큰 인증
            },
          );

          if (response.statusCode == 200) {
            return jsonDecode(utf8.decode(response.bodyBytes));
          }
          return {'success': false, 'message': '프로필 로딩 실패'};
        } catch (e) {
          return {'success': false, 'message': '서버 연결 오류'};
        }
      }
      static Future<Map<String, dynamic>> updateLoggedUserPhone({required String phone}) async {
          try {
            final token = AuthSession.token;
            if (token == null) return {'success': false, 'message': '로그인이 필요합니다.'};

            // 회원가입용(verify-code/)과 분리된, 정보 수정용 엔드포인트라고 가정합니다.
            // 백엔드에도 이 주소에 매핑되는 UpdateView가 있어야 합니다.
            final url = Uri.parse('$baseUrl/update-phone/');

            final response = await http.post(
              url,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Token $token', // 📍 누구의 번호를 바꿀지 알려주는 핵심
              },
              body: jsonEncode({'phone': phone}),
            );

            final data = jsonDecode(utf8.decode(response.bodyBytes));

            if (response.statusCode == 200 && data['success'] == true) {
              return {
                'success': true,
                'message': data['message'] ?? '전화번호가 성공적으로 갱신되었습니다.',
              };
            }

            return {
              'success': false,
              'message': data['message'] ?? '번호 갱신에 실패했습니다.'
            };
          } catch (e) {
            return {'success': false, 'message': '서버 연결 오류가 발생했습니다.'};
          }
        }
}

