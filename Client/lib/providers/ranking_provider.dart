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
  final String? roundId = ref.watch(rankingRoundIdProvider);
  debugPrint("[topRankings] 현재 라운드 ID: $roundId");

  if (roundId == null) {
    // 라운드 ID가 아직 설정되지 않으면 빈 리스트 반환
    debugPrint("[topRankings] 라운드 ID가 null입니다. 빈 스트림 반환");
    return const Stream.empty();
  }

  final dbRef = FirebaseDatabase.instance.ref('liveRank/$roundId');
  debugPrint("[topRankings] Firebase RTDB 경로: liveRank/$roundId");

  final query = dbRef.orderByChild('score').limitToLast(10);
  final controller = StreamController<List<RankEntry>>();

  // 먼저 경로 존재 여부 확인 (한 번만)
  dbRef
      .get()
      .then((snapshot) {
        debugPrint(
          "[topRankings] 초기 스냅샷 확인: 존재=${snapshot.exists}, 값 타입=${snapshot.value?.runtimeType}",
        );

        if (!snapshot.exists) {
          debugPrint("[topRankings] 경로가 존재하지 않습니다. 테스트 데이터 생성");
          // 테스트 데이터 생성 (선택 사항)
          final testData = {
            'testUser1': {
              'nick': 'TestUser1',
              'score': 100,
              'ts': DateTime.now().millisecondsSinceEpoch,
            },
          };
          dbRef
              .set(testData)
              .then((_) {
                debugPrint("[topRankings] 테스트 데이터 생성 완료");
              })
              .catchError((e) {
                debugPrint("[topRankings] 테스트 데이터 생성 실패: $e");
              });
        }
      })
      .catchError((e) {
        debugPrint("[topRankings] 초기 경로 확인 중 오류: $e");
      });

  final subscription = query.onValue.listen(
    (event) {
      final data = event.snapshot.value;
      debugPrint("[topRankings] 스냅샷 수신: 데이터 타입=${data?.runtimeType}");

      final List<RankEntry> rankings = [];

      // 데이터가 없는 경우
      if (data == null) {
        debugPrint("[topRankings] 데이터가 null입니다");
        if (!controller.isClosed) controller.add([]);
        return;
      }

      // 데이터 타입 확인
      if (data is! Map) {
        debugPrint("[topRankings] 데이터가 Map 형식이 아닙니다: $data");
        if (!controller.isClosed) controller.add([]);
        return;
      }

      // Map 형식의 데이터 처리
      try {
        data.forEach((key, value) {
          try {
            if (value is Map) {
              debugPrint("[topRankings] 항목 변환 시도: key=$key, value=$value");

              // 기존 RankEntry.fromRTDB 팩토리 메서드 사용
              final entry = RankEntry.fromRTDB(key.toString(), value);
              rankings.add(entry);
              debugPrint(
                "[topRankings] 항목 추가됨: uid=${entry.uid}, nick=${entry.nick}, score=${entry.score}",
              );
            } else {
              debugPrint(
                "[topRankings] 항목이 Map 형식이 아님: key=$key, value=$value",
              );
            }
          } catch (e) {
            debugPrint("[topRankings] 항목 변환 중 오류: $e");
          }
        });

        // 점수 내림차순, 같으면 타임스탬프 오름차순으로 정렬
        rankings.sort((a, b) {
          final scoreCompare = b.score.compareTo(a.score);
          return scoreCompare != 0
              ? scoreCompare
              : a.timestamp.compareTo(b.timestamp);
        });

        debugPrint("[topRankings] 총 ${rankings.length}개 항목 처리 완료");
      } catch (e) {
        debugPrint("[topRankings] 데이터 처리 중 오류: $e");
      }

      // 결과 전송
      if (!controller.isClosed) controller.add(rankings);
    },
    onError: (e) {
      debugPrint("[topRankings] 스트림 오류: $e");
      if (!controller.isClosed) controller.addError(e);
    },
  );

  ref.onDispose(() {
    debugPrint("[topRankings] provider 해제됨");
    subscription.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Firestore에서 가장 최근에 생성된 Round 문서의 ID를 조회하는 함수
/// 현재 시간에 해당하는 플레이 가능한 라운드를 조회하는 함수
/// 현재 시간에 해당하는 플레이 가능한 라운드를 조회하는 함수
/// 현재 시간에 해당하는 플레이 가능한 라운드를 조회하는 함수
Future<String> joinRound() async {
  debugPrint("[joinRound] 현재 시간에 맞는 라운드 조회 시작");
  try {
    // UTC 기준 현재 시간
    final now = Timestamp.now();
    final nowUtc = now.toDate();

    // 한국 시간으로 변환 (UTC+9)
    final nowKst = toKoreanTime(nowUtc);

    debugPrint("[joinRound] 현재 시간(UTC): $nowUtc");
    debugPrint("[joinRound] 현재 시간(KST): $nowKst");

    // 현재 상황에 맞는 라운드 검색
    // 1. 현재 시간이 submitCloseAt보다 이전인 라운드 검색
    final query =
        await FirebaseFirestore.instance
            .collection('rounds')
            .where('submitCloseAt', isGreaterThan: now)
            .orderBy('submitCloseAt')
            .limit(10)
            .get();

    debugPrint("[joinRound] 조회된 라운드 수: ${query.docs.length}");

    if (query.docs.isEmpty) {
      // 다음 라운드 조회
      final nextQuery =
          await FirebaseFirestore.instance
              .collection('rounds')
              .where('startAt', isGreaterThan: now)
              .orderBy('startAt')
              .limit(1)
              .get();

      if (nextQuery.docs.isEmpty) {
        throw Exception('현재 참가 가능한 라운드가 없고 예정된 라운드도 없습니다');
      }

      final roundId = nextQuery.docs.first.id;
      final startAt = nextQuery.docs.first.data()['startAt'] as Timestamp;
      final startAtUtc = startAt.toDate();
      final startAtKst = toKoreanTime(startAtUtc);

      debugPrint("[joinRound] 현재 참가 가능한 라운드 없음. 곧 시작될 라운드 ID: $roundId");
      debugPrint("[joinRound] 시작 시간(UTC): $startAtUtc");
      debugPrint("[joinRound] 시작 시간(KST): $startAtKst");

      return roundId;
    }

    // 2. entryCloseAt가 현재 시간보다 나중이고 startAt이 현재 시간보다 이전인 라운드 찾기
    for (var doc in query.docs) {
      final data = doc.data();
      final entryCloseAt = data['entryCloseAt'] as Timestamp;
      final startAt = data['startAt'] as Timestamp;

      if (entryCloseAt.compareTo(now) > 0 && startAt.compareTo(now) <= 0) {
        // 이 라운드는 이미 시작되었고 아직 참가 마감되지 않았음
        final startAtUtc = startAt.toDate();
        final entryCloseAtUtc = entryCloseAt.toDate();
        final startAtKst = toKoreanTime(startAtUtc);
        final entryCloseAtKst = toKoreanTime(entryCloseAtUtc);

        debugPrint("[joinRound] 현재 참가 및 플레이 가능한 라운드: ${doc.id}");
        debugPrint(
          "[joinRound] 시작(UTC): $startAtUtc, 참가 마감(UTC): $entryCloseAtUtc",
        );
        debugPrint(
          "[joinRound] 시작(KST): $startAtKst, 참가 마감(KST): $entryCloseAtKst",
        );

        return doc.id;
      }
    }

    // 3. 참가 마감은 됐지만 제출은 가능한 라운드
    final doc = query.docs.first;
    final data = doc.data();
    final startAt = data['startAt'] as Timestamp;
    final submitCloseAt = data['submitCloseAt'] as Timestamp;

    final startAtUtc = startAt.toDate();
    final submitCloseAtUtc = submitCloseAt.toDate();
    final startAtKst = toKoreanTime(startAtUtc);
    final submitCloseAtKst = toKoreanTime(submitCloseAtUtc);

    debugPrint("[joinRound] 참가 마감된 현재 진행 중인 라운드: ${doc.id}");
    debugPrint(
      "[joinRound] 시작(UTC): $startAtUtc, 제출 마감(UTC): $submitCloseAtUtc",
    );
    debugPrint(
      "[joinRound] 시작(KST): $startAtKst, 제출 마감(KST): $submitCloseAtKst",
    );

    return doc.id;
  } catch (e) {
    debugPrint("[joinRound] 오류 발생: $e");
    rethrow;
  }
}

// UTC 시간을 한국 시간(UTC+9)으로 변환하는 헬퍼 함수
DateTime toKoreanTime(DateTime utcTime) {
  return utcTime.add(Duration(hours: 9));
}
