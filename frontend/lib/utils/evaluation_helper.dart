import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../service/auth_session.dart';
import '../service/trip_service.dart';
import 'colors.dart';

class EvaluationHelper {
  static const String evaluatedRoomsKey = 'evaluated_rooms';

  static Future<List<String>> _getEvaluatedRoomIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(evaluatedRoomsKey) ?? [];
  }

  static Future<bool> isRoomEvaluated(int roomId) async {
    final evaluated = await _getEvaluatedRoomIds();
    return evaluated.contains(roomId.toString());
  }

  static Future<void> markRoomEvaluated(int roomId) async {
    final prefs = await SharedPreferences.getInstance();
    final evaluated = prefs.getStringList(evaluatedRoomsKey) ?? [];
    final idStr = roomId.toString();
    if (!evaluated.contains(idStr)) {
      evaluated.add(idStr);
      await prefs.setStringList(evaluatedRoomsKey, evaluated);
    }
  }

  static Future<void> showGlobalEvaluationDialog({
    required BuildContext context,
    required int roomId,
    required int tripId,
    required String roomName,
  }) async {
    if (await isRoomEvaluated(roomId)) return;

    final token = AuthSession.token ?? '';
    if (token.isEmpty) return;

    Map<String, dynamic> data;
    try {
      data = await TripService.getTripParticipants(
        token: token,
        roomId: roomId,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('참여자 목록을 불러오지 못했습니다: $e')),
      );
      return;
    }

    final rawList = data['participants'];
    if (rawList is! List) return;

    final participants = rawList
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final myUsername = AuthSession.username ?? '';
    final others = participants
        .where((p) => (p['username']?.toString() ?? '') != myUsername)
        .toList();

    if (!context.mounted) return;
    if (others.isEmpty) return;

    final ratings = <int, int>{};
    for (final p in others) {
      final uid = int.tryParse(p['user_id']?.toString() ?? '') ?? 0;
      if (uid != 0) {
        ratings[uid] = 5;
      }
    }
    if (ratings.isEmpty) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Text(
                '동승자 평가',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppColors.secondary,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$roomName을(를) 함께한 사람들을 평가해주세요.',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...others.map((p) {
                        final uid =
                            int.tryParse(p['user_id']?.toString() ?? '') ?? 0;
                        final un = p['username']?.toString() ?? '';
                        final score = ratings[uid] ?? 5;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '@$un',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.secondary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  for (int star = 1; star <= 5; star++)
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 36,
                                        minHeight: 36,
                                      ),
                                      onPressed: () {
                                        setLocal(() {
                                          ratings[uid] = star;
                                        });
                                      },
                                      icon: Icon(
                                        star <= score
                                            ? Icons.star
                                            : Icons.star_border,
                                        color: star <= score
                                            ? AppColors.accent
                                            : AppColors.gray,
                                        size: 28,
                                      ),
                                    ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '$score점',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.gray,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    await markRoomEvaluated(roomId);
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: const Text('건너뛰기'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final payload = ratings.entries
                        .map(
                          (e) => <String, dynamic>{
                            'to_user_id': e.key,
                            'rating': e.value,
                          },
                        )
                        .toList();
                    try {
                      await TripService.submitTripReviews(
                        token: token,
                        tripId: tripId,
                        reviews: payload,
                      );
                      await markRoomEvaluated(roomId);
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('평가가 완료되었습니다.'),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('평가 제출 실패: $e')),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('제출'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
