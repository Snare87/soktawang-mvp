import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore import
import 'package:firebase_auth/firebase_auth.dart'; // Auth import

// --- Auth 관련 Provider ---

final authStateChangesProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

final userIdProvider = Provider<String?>((ref) {
  return ref.watch(authStateChangesProvider).value?.uid;
});

// --- User Data 관련 Provider ---

final userDocStreamProvider = StreamProvider<DocumentSnapshot?>((ref) {
  final userId = ref.watch(userIdProvider);
  if (userId == null) {
    return Stream.value(null);
  } else {
    // users 컬렉션에서 해당 ID의 문서 변경 사항을 실시간 감시
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots();
  }
});

/// 남은 무료 플레이 횟수를 제공하는 Provider (Firestore 데이터 기반)
final freePlaysProvider = Provider<int>((ref) {
  // userDocStreamProvider를 watch하여 Firestore 문서 스냅샷을 가져옴
  final userDocSnapshot = ref.watch(userDocStreamProvider);

  // 스냅샷에 데이터가 있고(로딩 완료), 문서가 실제로 존재할 때 값 추출 시도
  if (userDocSnapshot.hasValue && userDocSnapshot.value?.exists == true) {
    final data = userDocSnapshot.value!.data() as Map<String, dynamic>?;
    // 'freePlaysLeft' 필드가 있으면 int 타입으로 가져오고, 없거나 타입이 다르면 0 반환
    final plays = data?['freePlaysLeft'] as int? ?? 0;
    return plays;
  } else {
    // 로딩 중이거나, 에러가 발생했거나, 문서가 존재하지 않으면 0 반환
    return 0;
  }
});

/// Firestore에서 다음 참가 가능한 라운드 정보를 가져오는 Provider
final nextAvailableRoundProvider = StreamProvider<DocumentSnapshot?>((ref) {
  final now = Timestamp.now(); // 현재 시간

  // 'rounds' 컬렉션에서 entryCloseAt이 현재 시간 이후인 문서들을
  // entryCloseAt 기준으로 오름차순 정렬하고, 가장 첫 번째 문서만 가져옴
  final query = FirebaseFirestore.instance
      .collection('rounds')
      .where('entryCloseAt', isGreaterThan: now) // 참가 마감 시간이 지나지 않은 라운드
      .orderBy('entryCloseAt', descending: false) // 가장 빨리 마감되는 라운드 먼저
      .limit(1); // 가장 가까운 라운드 하나만

  // 쿼리 결과의 스냅샷 스트림을 반환
  return query.snapshots().map((querySnapshot) {
    debugPrint("--- [NextAvailableRoundProvider] Snapshot Received ---");
    debugPrint("Docs count: ${querySnapshot.docs.length}");

    if (querySnapshot.docs.isNotEmpty) {
      final roundDoc = querySnapshot.docs.first;
      debugPrint(
        "[HomeProvider] Next round ID: ${roundDoc.id}, entryCloseAt: ${roundDoc.data()['entryCloseAt']}",
      );
      return roundDoc;
    } else {
      debugPrint(
        "[HomeProvider] No upcoming rounds with entry time available.",
      );
      return null;
    }
  });
});

/// 다음 참가 마감까지 남은 시간을 제공하는 Provider
final nextEntryCloseTimeProvider = Provider<Duration>((ref) {
  final roundSnapshotAsync = ref.watch(nextAvailableRoundProvider);

  return roundSnapshotAsync.when(
    data: (DocumentSnapshot? doc) {
      if (doc != null && doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null && data.containsKey('entryCloseAt')) {
          final closeAt = data['entryCloseAt'] as Timestamp;
          final now = Timestamp.now();
          final difference = closeAt.toDate().difference(now.toDate());

          // 디버그 로그
          debugPrint(
            "[HomeProvider] Current time: ${now.toDate()}, Entry close at: ${closeAt.toDate()}",
          );
          debugPrint(
            "[HomeProvider] Time remaining: ${difference.inMinutes} min ${difference.inSeconds % 60} sec",
          );

          return difference.isNegative ? Duration.zero : difference;
        }
      }
      debugPrint(
        "[HomeProvider] No valid entry close time found. Returning Duration.zero",
      );
      return Duration.zero; // 문서가 없거나 필드가 없으면 0초
    },
    loading: () => const Duration(days: 999), // 로딩 중일 때는 큰 값 사용
    error: (err, stack) {
      debugPrint("[HomeProvider] Error getting next entry close time: $err");
      return Duration.zero; // 에러 시 0초
    },
  );
});

/// 기존 Provider는 유지 (필요시 사용)
final nextRoundStartTimeProvider = StreamProvider<Timestamp?>((ref) {
  final now = Timestamp.now(); // 현재 시간

  // 'rounds' 컬렉션에서 'startAt' 필드가 현재 시간 이후인 문서들을
  // 'startAt' 필드 기준으로 오름차순 정렬하고, 가장 첫 번째 문서(가장 가까운 라운드)만 가져옴
  final query = FirebaseFirestore.instance
      .collection('rounds')
      .where('status', isEqualTo: 'pending') // 'pending' 상태인 라운드만 고려
      .where('startAt', isGreaterThan: now) // 현재 시간 이후에 시작하는 라운드만
      .orderBy('startAt', descending: false) // 가장 먼저 시작하는 순서대로 정렬
      .limit(1); // 가장 가까운 라운드 하나만

  // 쿼리 결과의 스냅샷 스트림을 반환
  return query.snapshots().map((querySnapshot) {
    if (querySnapshot.docs.isNotEmpty) {
      // 문서가 존재하면 첫 번째 문서의 'startAt' 필드 반환
      final roundDoc = querySnapshot.docs.first;
      final data = roundDoc.data();
      debugPrint(
        "[HomeProvider] Next round startAt: ${data['startAt']}",
      ); // 디버그 로그
      return data['startAt'] as Timestamp?;
    } else {
      // 예정된 라운드가 없으면 null 반환
      debugPrint("[HomeProvider] No upcoming pending rounds found."); // 디버그 로그
      return null;
    }
  });
});

/// 다음 라운드까지 남은 시간을 Duration 형태로 제공하는 Provider (기존 코드 유지)
final nextAlarmTimeProvider = Provider<Duration>((ref) {
  // nextRoundStartTimeProvider를 watch하여 다음 라운드 시작 시간을 가져옴
  final nextRoundStartTimeAsyncValue = ref.watch(nextRoundStartTimeProvider);

  // nextRoundStartTimeAsyncValue의 상태에 따라 Duration 반환
  return nextRoundStartTimeAsyncValue.when(
    data: (Timestamp? startTime) {
      if (startTime != null) {
        final now = Timestamp.now();
        // 시작 시간과 현재 시간의 차이를 계산
        final difference = startTime.toDate().difference(now.toDate());
        // 차이가 음수이면(이미 지난 시간) Duration.zero 반환
        return difference.isNegative ? Duration.zero : difference;
      }
      return Duration.zero; // 시작 시간이 없으면 0초
    },
    loading:
        () => const Duration(
          days: 999,
        ), // 로딩 중일 때는 매우 큰 값 (또는 특정 상태값) - 화면에서 구분하기 위함
    error: (err, stack) => Duration.zero, // 에러 발생 시 0초
  );
});
