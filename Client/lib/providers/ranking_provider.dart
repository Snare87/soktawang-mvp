import 'dart:async'; // StreamController 사용 위해 import
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_database/firebase_database.dart'; // RTDB 패키지 import

// 랭킹 데이터 모델 클래스 정의
// RTDB 에서 받아온 데이터를 Dart 객체로 변환하기 위함
class RankEntry {
  final String uid;
  final String nick;
  final int score;
  final int timestamp; // RTDB 타임스탬프 (밀리초)

  RankEntry({
    required this.uid,
    required this.nick,
    required this.score,
    required this.timestamp,
  });

  // RTDB의 Map 데이터로부터 RankEntry 객체를 만드는 팩토리 생성자
  factory RankEntry.fromRTDB(String uid, Map<dynamic, dynamic> data) {
    return RankEntry(
      uid: uid,
      // 필드가 없거나 타입이 안 맞을 경우 기본값 사용 (null safety)
      nick: data['nick'] as String? ?? 'Unknown',
      score: data['score'] as int? ?? 0,
      timestamp: data['ts'] as int? ?? 0,
    );
  }
}

// --- Providers ---

// 현재 조회할 라운드의 ID를 제공하는 Provider (임시)
// TODO: 나중에 실제 라운드 정보를 관리하는 다른 Provider와 연결해야 함
final currentRoundIdProvider = Provider<String>((ref) {
  return 'test-round-001'; // 테스트용 고정 라운드 ID
});

// 실시간 Top 10 랭킹 리스트를 제공하는 StreamProvider
final topRankingsProvider = StreamProvider<List<RankEntry>>((ref) {
  // 현재 라운드 ID 가져오기
  final roundId = ref.watch(currentRoundIdProvider);

  // RTDB에서 해당 라운드의 랭킹 데이터 경로 참조
  final dbRef = FirebaseDatabase.instance.ref('liveRank/$roundId');

  // 점수(score) 기준으로 정렬하고, 마지막 10개(상위 10개)만 가져오는 쿼리 생성
  // RTDB는 기본 오름차순 정렬, limitToLast는 가장 큰 값부터 10개를 가져옴
  final query = dbRef.orderByChild('score').limitToLast(10);

  // StreamController: 비동기 이벤트(DB 업데이트)를 Stream으로 변환하여 전달
  final controller = StreamController<List<RankEntry>>();

  // query.onValue: 해당 경로의 데이터 변경을 실시간으로 감지하는 리스너
  final subscription = query.onValue.listen(
    (DatabaseEvent event) {
      // --- 디버그 로그 추가 시작 ---
      print("--- RTDB Ranking Provider: Snapshot Received ---");
      print(
        "Snapshot Key: ${event.snapshot.key}",
      ); // 보통 라운드 ID (예: test-round-001)
      print(
        "Snapshot Value Type: ${event.snapshot.value?.runtimeType}",
      ); // 받아온 데이터의 실제 타입
      print("Snapshot Raw Value: ${event.snapshot.value}"); // 받아온 데이터 전체 내용
      // --- 디버그 로그 추가 끝 ---
      // 데이터 변경 이벤트 발생 시
      final data = event.snapshot.value; // 변경된 데이터 스냅샷 가져오기
      final List<RankEntry> rankings = []; // 랭킹 리스트 초기화

      if (data != null && data is Map) {
        // RTDB에서 가져온 데이터는 Map 형태 ({ uid1: {score:.., nick:..}, uid2: {...} })
        data.forEach((key, value) {
          // 각 사용자(key=uid) 데이터 처리
          if (value is Map) {
            // Map 데이터를 RankEntry 객체로 변환하여 리스트에 추가
            rankings.add(RankEntry.fromRTDB(key as String, value));
          }
        });

        // 클라이언트에서 최종 정렬 수행: 점수 내림차순, 동점 시 타임스탬프 오름차순(먼저 등록된 사람 우선)
        rankings.sort((a, b) {
          final scoreComp = b.score.compareTo(a.score); // 점수 비교 (내림차순)
          if (scoreComp != 0) {
            return scoreComp; // 점수가 다르면 점수 순으로 정렬
          }
          // 점수가 같으면 타임스탬프 비교 (오름차순)
          return a.timestamp.compareTo(b.timestamp);
        });
      }

      // 정렬된 랭킹 리스트를 StreamController를 통해 Provider 구독자에게 전달
      if (!controller.isClosed) {
        controller.add(rankings);
      }
    },
    onError: (Object error) {
      // 데이터 수신 중 에러 발생 시
      print("Error listening to rankings: $error");
      if (!controller.isClosed) {
        controller.addError(error); // 에러도 스트림으로 전달
      }
    },
  );

  // Provider가 더 이상 사용되지 않을 때(화면 벗어남 등) 호출됨
  ref.onDispose(() {
    print(
      "Disposing ranking provider - closing stream controller and DB subscription",
    );
    // 데이터베이스 리스너 구독 취소 (메모리 누수 방지)
    subscription.cancel();
    // StreamController 닫기
    controller.close();
  });

  // StreamController가 제공하는 Stream을 반환
  return controller.stream;
});
