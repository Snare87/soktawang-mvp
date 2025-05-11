import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// 최신 라운드를 가져오는 Provider
final defaultRoundIdProvider = FutureProvider<String>((ref) async {
  debugPrint("[defaultRound] 시작");
  final snap =
      await FirebaseFirestore.instance
          .collection('rounds')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
  debugPrint("[defaultRound] snap.docs.length = ${snap.docs.length}"); // ← 추가

  if (snap.docs.isEmpty) throw Exception('생성된 라운드가 없습니다');
  final String latestId = snap.docs.first.id;
  debugPrint("[defaultRound] 최신 라운드 ID = $latestId");
  return latestId;
});

/// 사용 가능한 라운드 ID 목록
final availableRoundsProvider = FutureProvider<List<String>>((ref) async {
  debugPrint("[availableRounds] 시작"); // ← 추가

  final snapshot =
      await FirebaseFirestore.instance
          .collection('rounds')
          .orderBy('createdAt', descending: true)
          .get();
  final List<String> ids = snapshot.docs.map((doc) => doc.id).toList();
  debugPrint("[availableRounds] IDs = $ids");
  return ids;
});

/// Round 모델
class Round {
  final String id;
  final String sentenceId;
  Round({required this.id, required this.sentenceId});
}

/// 선택된 라운드 ID (nullable)
final currentRoundIdProvider = StateProvider<String?>((ref) => null);

/// 선택된 Round 문서
final roundDocumentProvider = FutureProvider<Round>((ref) async {
  final rid = ref.read(currentRoundIdProvider);
  if (rid == null) throw Exception('Round ID가 설정되지 않음');
  final doc =
      await FirebaseFirestore.instance.collection('rounds').doc(rid).get();
  final data = doc.data();
  if (data == null) throw Exception('라운드 문서가 없습니다: $rid');
  return Round(id: doc.id, sentenceId: data['sentenceId'] as String);
});
