import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

// Round 문서의 데이터를 쉽게 접근하기 위한 모델 클래스
class Round {
  final String id;
  final String sentenceId;
  final Map<String, dynamic> data;

  Round({required this.id, required this.sentenceId, required this.data});

  factory Round.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Round(
      id: doc.id,
      sentenceId: data['sentenceId'] as String? ?? '',
      data: data,
    );
  }
}

// 수정된 Provider 구조
// 1. 게임 플레이에 사용되는 현재 라운드 ID
final gameRoundIdProvider = StateProvider<String?>((ref) => null);

// 2. 랭킹 화면에서 사용하는 선택된 라운드 ID (기존 selectedRoundIdProvider와 유사)
final rankingRoundIdProvider = StateProvider<String?>((ref) => null);

// Round ID를 기반으로 해당 Round 문서를 제공하는 FutureProvider
final roundDocumentProvider = FutureProvider<Round>((ref) async {
  final roundId = ref.watch(gameRoundIdProvider); // currentRoundIdProvider에서 변경
  debugPrint("[roundDocumentProvider] 요청된 라운드 ID: $roundId");

  if (roundId == null) {
    throw Exception('Round ID가 설정되지 않았습니다');
  }

  try {
    final doc =
        await FirebaseFirestore.instance
            .collection('rounds')
            .doc(roundId)
            .get();

    if (!doc.exists) {
      throw Exception('존재하지 않는 Round ID: $roundId');
    }

    // DocumentSnapshot에서 Round 객체로 변환
    final round = Round.fromFirestore(doc);
    debugPrint(
      "[roundDocumentProvider] 라운드 문서 로드 완료: ${round.id}, sentenceId=${round.sentenceId}",
    );
    return round;
  } catch (e) {
    debugPrint("[roundDocumentProvider] 라운드 문서 로드 중 오류: $e");
    rethrow;
  }
});

// 가장 기본 라운드(최신 라운드)의 ID를 조회하는 FutureProvider
final defaultRoundIdProvider = FutureProvider<String>((ref) async {
  debugPrint("[defaultRoundIdProvider] 최신 라운드 ID 조회 시작");

  try {
    final query =
        await FirebaseFirestore.instance
            .collection('rounds')
            .orderBy('createdAt', descending: true)
            .limit(1)
            .get();

    if (query.docs.isEmpty) {
      const errorMsg = '생성된 라운드가 없습니다';
      debugPrint("[defaultRoundIdProvider] $errorMsg");
      throw Exception(errorMsg);
    }

    final roundId = query.docs.first.id;
    debugPrint("[defaultRoundIdProvider] 최신 라운드 ID: $roundId");

    // defaultRoundIdProvider 조회 시 자동으로 currentRoundIdProvider 초기화 (최초 한 번만)
    if (ref.read(rankingRoundIdProvider) == null) {
      debugPrint(
        "[defaultRoundIdProvider] rankingRoundIdProvider 초기화: $roundId",
      );
      ref.read(rankingRoundIdProvider.notifier).state = roundId;
    }

    return roundId;
  } catch (e) {
    debugPrint("[defaultRoundIdProvider] 오류 발생: $e");
    rethrow;
  }
});
