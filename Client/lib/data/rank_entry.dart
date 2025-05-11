// lib/data/rank_entry.dart

/// RTDB에서 받아온 한 사용자의 랭킹 정보를 담는 모델 클래스
class RankEntry {
  /// 사용자 고유 ID
  final String uid;

  /// 사용자 닉네임
  final String nick;

  /// 점수
  final int score;

  /// 제출 시각(밀리초)
  final int timestamp;

  RankEntry({
    required this.uid,
    required this.nick,
    required this.score,
    required this.timestamp,
  });

  /// RTDB 스냅샷의 Map 데이터를 RankEntry로 변환
  factory RankEntry.fromRTDB(String uid, Map<dynamic, dynamic> data) {
    return RankEntry(
      uid: uid,
      nick: data['nick'] as String? ?? 'Unknown',
      score: data['score'] as int? ?? 0,
      timestamp: data['ts'] as int? ?? 0,
    );
  }
}
