class MatchingRequest {
  final int tripId;
  final int creatorUserId;
  final int leaderUserId;
  final String departName;
  final double departLat;
  final double departLng;
  final String arriveName;
  final double arriveLat;
  final double arriveLng;
  final DateTime departTime;
  final int capacity;
  final String seatPosition;

  MatchingRequest({
    required this.tripId,
    required this.creatorUserId,
    required this.leaderUserId,
    required this.departName,
    required this.departLat,
    required this.departLng,
    required this.arriveName,
    required this.arriveLat,
    required this.arriveLng,
    required this.departTime,
    required this.capacity,
    required this.seatPosition,
  });

  // 객체를 JSON 맵으로 변환 (백엔드 전송용)
  Map<String, dynamic> toJson() {
    return {
      'trip_id': tripId,
      'creator_user_id': creatorUserId,
      'leader_user_id': leaderUserId,
      'depart_name': departName,
      'depart_lat': departLat,
      'depart_lng': departLng,
      'arrive_name': arriveName,
      'arrive_lat': arriveLat,
      'arrive_lng': arriveLng,
      'depart_time': departTime.toIso8601String(), // ISO8601 형식 문자열로 변환
      'capacity': capacity,
      'seat_position': seatPosition,
      'created_at': DateTime.now().toIso8601String(),
    };
  }
}