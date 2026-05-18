// ============================================================
// lib/utils/colors.dart — 앱 전체 색상 상수 관리
// ============================================================
// 여기서 색상을 바꾸면 앱 전체에 자동 적용
// ============================================================
import 'package:flutter/material.dart';

class AppColors {
  AppColors._(); // 인스턴스 생성 방지 (static 전용 클래스)

  // 브랜드 메인 컬러
  static const Color primary     = Color(0xFF1F7A4D); // Forest Green
  static const Color primaryDark = Color(0xFF155C38); // 진한 그린 (버튼 pressed)
  static const Color primaryLight= Color(0xFFEBF5EF); // 연한 그린 (배경, 태그)

  // 보조 컬러
  static const Color secondary   = Color(0xFF1A1A2E); // Deep Navy (텍스트, 헤더)
  static const Color accent      = Color(0xFFFFD166); // Amber Yellow (별점, 강조)
  static const Color success     = Color(0xFF6DBF92); // Mint Green (성공, 온라인)
  static const Color red         = Color(0xFFFF6B6B); // 경고, 오류, 신고

  // 텍스트
  static const Color text        = Color(0xFF1A1A2E);
  static const Color textSub     = Color(0xFF8A8FA3); // 보조 텍스트

  // 배경 / 테두리
  static const Color bg          = Color(0xFFF5F3EF); // 앱 전체 배경
  static const Color surface     = Color(0xFFFFFFFF); // 카드 배경
  static const Color border      = Color(0xFFE8E5DF); // 테두리
  static const Color gray        = Color(0xFF8A8FA3); // 비활성 아이콘/텍스트
}