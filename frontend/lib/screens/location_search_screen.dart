// ============================================================
// lib/screens/location_search_screen.dart
// ============================================================
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../utils/colors.dart';

// 장소 검색 화면
class LocationSearchScreen extends StatefulWidget {
  final String title; // '출발지' 또는 '목적지'
  const LocationSearchScreen({super.key, required this.title});

  @override
  State<LocationSearchScreen> createState() => _LocationSearchScreenState();
}

class _LocationSearchScreenState extends State<LocationSearchScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isLoading = false;
  List<Map<String, dynamic>> _searchResults = [];
  String? _errorMessage;

  static const String _kakaoApiKey = 'KakaoAK 1e744bb93d1f2fd877289039342148d2';
  static const String _kakaoApiUrl = 'https://dapi.kakao.com/v2/local/search/keyword.json';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // 카카오 장소 검색 API 호출
  Future<void> _searchPlaces(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final uri = Uri.parse('$_kakaoApiUrl?query=$query');
      final response = await http.get(
        uri,
        headers: {'Authorization': _kakaoApiKey},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final documents = data['documents'] as List<dynamic>;

        setState(() {
          _searchResults = documents.map((doc) => {
            'place_name': doc['place_name'] as String,
            'address_name': doc['address_name'] as String,
            'road_address_name': doc['road_address_name'] as String,
            'x': doc['x'] as String,  // 경도 (longitude)
            'y': doc['y'] as String,  // 위도 (latitude)
          }).toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = '검색에 실패했습니다. (${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '검색 중 오류가 발생했습니다: $e';
        _isLoading = false;
      });
    }
  }

  // 장소 선택 시 결과 반환
  void _selectPlace(Map<String, dynamic> place) {
    // x = 경도(lng), y = 위도(lat)
    final result = {
      'name': place['place_name'],
      'address': place['road_address_name'].isNotEmpty
          ? place['road_address_name']
          : place['address_name'],
      'lat': double.parse(place['y']),  // 위도
      'lng': double.parse(place['x']),  // 경도
    };
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.secondary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${widget.title} 검색',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.secondary),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: Column(
        children: [
          // 검색 입력창
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl,
              autofocus: false,
              decoration: InputDecoration(
                hintText: '${widget.title}를 입력하세요...',
                hintStyle: const TextStyle(fontSize: 14, color: AppColors.gray),
                prefixIcon: const Icon(Icons.search, color: AppColors.gray),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppColors.gray),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {
                            _searchResults = [];
                            _errorMessage = null;
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onSubmitted: _searchPlaces,
              onChanged: (text) => setState(() {}), // suffixIcon 갱신을 위해
            ),
          ),

          // 검색 버튼
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () => _searchPlaces(_searchCtrl.text.trim()),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('검색', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 검색 결과 목록
          Expanded(
            child: _buildSearchResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppColors.red, size: 48),
            const SizedBox(height: 12),
            Text(_errorMessage!, style: const TextStyle(color: AppColors.red)),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_on_outlined, color: AppColors.gray, size: 64),
            const SizedBox(height: 16),
            Text(
              _searchCtrl.text.isEmpty
                  ? '장소 이름을 입력하고 검색해보세요'
                  : '검색 결과가 없습니다',
              style: const TextStyle(color: AppColors.gray, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final place = _searchResults[index];
        final address = place['road_address_name'].isNotEmpty
            ? place['road_address_name']
            : place['address_name'];

        return GestureDetector(
          onTap: () => _selectPlace(place),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.location_on, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place['place_name'],
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.secondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        address,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.gray,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.gray, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}
