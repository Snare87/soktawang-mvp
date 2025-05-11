import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_database/firebase_database.dart'; // RTDB 패키지
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore 패키지
import '../data/rank_entry.dart'; // RankEntry 모델
import 'round_provider.dart'; // currentRoundIdProvider
import 'package:flutter/foundation.dart';

// --- Providers ---

/// 실시간 Top 10 랭킹 리스트를 제공하는 StreamProvider
final topRankingsProvider = StreamProvider<List<RankEntry>>((ref) {
  final String? roundId = ref.watch(currentRoundIdProvider);
  debugPrint("[topRankings] watching roundId = $roundId"); // ← 추가

  if (roundId == null) {
    // 라운드 ID가 아직 설정되지 않으면 빈 리스트 반환
    return const Stream.empty();
  }

  final dbRef = FirebaseDatabase.instance.ref('liveRank/$roundId');
  final query = dbRef.orderByChild('score').limitToLast(10);
  final controller = StreamController<List<RankEntry>>();

  final subscription = query.onValue.listen(
    (event) {
      debugPrint(
        "[topRankings] snapshot received: ${event.snapshot.value}",
      ); // ← 추가

      final data = event.snapshot.value;
      final List<RankEntry> rankings = [];
      if (data != null && data is Map) {
        data.forEach((key, value) {
          if (value is Map) {
            rankings.add(RankEntry.fromRTDB(key as String, value));
          }
        });
        rankings.sort((a, b) {
          final c = b.score.compareTo(a.score);
          return c != 0 ? c : a.timestamp.compareTo(b.timestamp);
        });
      }
      if (!controller.isClosed) controller.add(rankings);
    },
    onError: (e) {
      if (!controller.isClosed) controller.addError(e);
    },
  );

  ref.onDispose(() {
    subscription.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Firestore에서 가장 최근에 생성된 Round 문서의 ID를 조회하는 함수
Future<String> joinRound() async {
  final query =
      await FirebaseFirestore.instance
          .collection('rounds')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
  if (query.docs.isEmpty) {
    throw Exception('생성된 라운드가 없습니다');
  }
  return query.docs.first.id;
}
