import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore 패키지
import '../providers/home_providers.dart';
import '../providers/ranking_provider.dart';
import '../providers/round_provider.dart'; // currentRoundIdProvider
import 'lobby_view.dart';
import '../services/notification_service.dart';
import '../providers/round_alarm_scheduler_provider.dart';
import '../data/rank_entry.dart';

// 사용 가능한 모든 라운드 목록을 제공하는 FutureProvider
final availableRoundsProvider = FutureProvider<List<RoundInfo>>((ref) async {
  debugPrint("[availableRounds] 라운드 목록 조회 시작");

  try {
    final querySnapshot =
        await FirebaseFirestore.instance
            .collection('rounds')
            .orderBy('startAt', descending: true) // 시작 시간 기준 내림차순
            .get();

    final rounds =
        querySnapshot.docs.map((doc) {
          final data = doc.data();

          // roundId 필드에서 ID를 가져오거나, 문서 ID를 사용
          final roundId = data['roundId'] as String? ?? doc.id;

          // 시작 시간 추출
          final startAt = data['startAt'] as Timestamp?;

          return RoundInfo(
            id: roundId,
            documentId: doc.id,
            startAt: startAt ?? Timestamp.now(),
            status: data['status'] as String? ?? 'unknown',
          );
        }).toList();

    debugPrint("[availableRounds] ${rounds.length}개 라운드 로드됨");
    return rounds;
  } catch (e) {
    debugPrint("[availableRounds] 오류 발생: $e");
    rethrow;
  }
});

// 라운드 정보를 담는 모델 클래스
class RoundInfo {
  final String id; // roundId 필드 값 (실제 앱에서 사용하는 ID)
  final String documentId; // Firestore 문서 ID
  final Timestamp startAt; // 시작 시간
  final String status; // 상태

  RoundInfo({
    required this.id,
    required this.documentId,
    required this.startAt,
    required this.status,
  });

  // UI에 표시할 라운드 이름
  String get displayName {
    final date = startAt.toDate();
    final dateStr = '${date.month}/${date.day}';
    final timeStr =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    // 시간만 표시
    return '라운드 #${date.hour}${date.minute} ($dateStr $timeStr)';
  }

  @override
  String toString() => displayName;
}

class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> {
  Timer? _timer;
  Duration _currentRemainingTime = Duration.zero;
  bool _isTimerInitializedByProvider = false;
  bool _isLoadingRound = false; // 라운드 ID 로딩 상태

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      setState(() => _isLoadingRound = true);

      try {
        // 사용 가능한 라운드 목록 로드
        final rounds = await ref.read(availableRoundsProvider.future);

        if (rounds.isNotEmpty) {
          // 현재 라운드 ID가 없으면 최신 라운드 ID 가져오기
          final currentRoundId = ref.read(currentRoundIdProvider);
          if (currentRoundId == null) {
            debugPrint("[HomeView] 최신 라운드 ID 설정: ${rounds.first.id}");
            if (mounted) {
              ref.read(currentRoundIdProvider.notifier).state = rounds.first.id;
            }
          } else {
            debugPrint("[HomeView] 이미 라운드 ID가 설정되어 있음: $currentRoundId");
          }
        }
      } catch (e) {
        debugPrint("[HomeView] 라운드 초기화 오류: $e");
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('라운드 정보를 가져오는데 실패했습니다: $e')));
        }
      } finally {
        if (mounted) {
          setState(() => _isLoadingRound = false);
        }
      }

      // 알람 설정 처리 (기존 코드)
      final bool alarmsCurrentlyEnabled = ref.read(alarmSettingsProvider);
      if (alarmsCurrentlyEnabled) {
        ref
            .read(roundAlarmSchedulerProvider)
            .refreshAlarms()
            .then((_) {
              debugPrint('[HomeView] initState: 다음 알람 세트 스케줄링 시도 완료.');
            })
            .catchError((e) {
              debugPrint('[HomeView] initState: 알람 스케줄링 중 오류: $e');
            });
      } else {
        debugPrint('[HomeView] initState: 알람이 꺼져있어 스케줄링하지 않음.');
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _initializeOrResetTimer(Duration newRemainingTime) {
    if (newRemainingTime.inDays > 900) {
      _timer?.cancel();
      if (mounted) {
        setState(() {
          _currentRemainingTime = newRemainingTime;
        });
      }
      return;
    }

    _timer?.cancel();
    if (mounted) {
      setState(() {
        _currentRemainingTime = newRemainingTime;
      });
    }

    if (_currentRemainingTime.inSeconds > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timerInstance) {
        if (_currentRemainingTime.inSeconds <= 0) {
          timerInstance.cancel();
          if (mounted) {
            setState(() {
              _currentRemainingTime = Duration.zero;
            });
            // 중요: 한 라운드가 끝나고 다음 라운드로 넘어갈 때 (타이머가 0이 될 때)
            // 알람 설정을 다시 확인하고 다음 알람들을 스케줄링합니다.
            final bool alarmsCurrentlyEnabled = ref.read(alarmSettingsProvider);
            if (alarmsCurrentlyEnabled) {
              ref
                  .read(roundAlarmSchedulerProvider)
                  .refreshAlarms()
                  .then((_) {
                    debugPrint('[HomeView] 라운드 전환: 다음 알람 세트 스케줄링 시도 완료.');
                  })
                  .catchError((e) {
                    debugPrint('[HomeView] 라운드 전환 중 알람 스케줄링 오류: $e');
                  });
            }
          }
        } else {
          if (mounted) {
            setState(() {
              _currentRemainingTime =
                  _currentRemainingTime - const Duration(seconds: 1);
            });
          } else {
            timerInstance.cancel();
          }
        }
      });
    }
  }

  String formatDuration(Duration d) {
    if (d.inDays > 900) {
      return "--:--";
    }
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  // 라운드 선택 팝업 표시
  void _showRoundSelectionDialog() async {
    final rounds = await ref.read(availableRoundsProvider.future);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('라운드 선택'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300, // 높이 제한
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: rounds.length,
              itemBuilder: (context, index) {
                final round = rounds[index];
                final date = round.startAt.toDate();
                return ListTile(
                  title: Text(
                    '라운드 #${date.hour}${date.minute} (${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')})',
                  ),
                  subtitle: Text('상태: ${round.status}'),
                  onTap: () {
                    // 선택한 라운드 ID로 currentRoundIdProvider 업데이트
                    ref.read(currentRoundIdProvider.notifier).state = round.id;
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final int freePlays = ref.watch(freePlaysProvider);
    final currentRoundId = ref.watch(currentRoundIdProvider);
    final availableRoundsAsync = ref.watch(availableRoundsProvider);

    ref.listen<Duration>(nextAlarmTimeProvider, (
      previousDuration,
      newDuration,
    ) {
      if (newDuration.inDays > 900 && _isTimerInitializedByProvider) {
        return;
      }
      _initializeOrResetTimer(newDuration);
      if (!(newDuration.inDays > 900)) {
        _isTimerInitializedByProvider = true;
      }
    });

    final String formattedTime = formatDuration(_currentRemainingTime);
    final isAlarmOn = ref.watch(alarmSettingsProvider);

    // 현재 선택된 라운드 정보 가져오기
    String currentRoundDisplay = '라운드 정보 로드 중...';
    availableRoundsAsync.whenData((rounds) {
      for (final round in rounds) {
        if (round.id == currentRoundId) {
          final date = round.startAt.toDate();
          currentRoundDisplay =
              '라운드 #${date.hour}${date.minute} (${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')})';
          break;
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('속타왕 홈'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '라운드 새로고침',
            onPressed: () {
              ref.invalidate(availableRoundsProvider);
              ref.invalidate(topRankingsProvider);
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Row(
              children: [
                Icon(
                  isAlarmOn
                      ? Icons.notifications_active
                      : Icons.notifications_off_outlined,
                ),
                Consumer(
                  builder: (context, ref, child) {
                    final bool currentAlarmState = ref.watch(
                      alarmSettingsProvider,
                    );
                    return Switch(
                      value: currentAlarmState,
                      onChanged: (bool value) async {
                        await ref
                            .read(alarmSettingsProvider.notifier)
                            .setAlarmEnabled(value);
                        if (!context.mounted) return;

                        final messenger = ScaffoldMessenger.of(context);
                        messenger.removeCurrentSnackBar();

                        if (value) {
                          try {
                            await ref
                                .read(roundAlarmSchedulerProvider)
                                .refreshAlarms();
                            if (!mounted) return;

                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  '라운드 알림이 켜졌습니다. 다음 라운드부터 알림이 예약됩니다.',
                                ),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;

                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('알림 예약 중 오류: $e'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        } else {
                          ref
                              .read(notificationServiceProvider)
                              .cancelAllNotifications();
                          if (!mounted) return;

                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('라운드 알림이 꺼졌습니다. 예약된 모든 알림이 취소됩니다.'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      body:
          _isLoadingRound
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Column(
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.local_activity_outlined,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '남은 무료 플레이: $freePlays회',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer_outlined, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                '다음 라운드까지: $formattedTime',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          // 라운드별 랭킹 확인 텍스트 (별도 행으로 배치)
                          Text(
                            '라운드별 랭킹 확인',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8), // 간격 추가
                          // 라운드 선택 드롭다운 버튼 (별도 행으로 배치, 전체 너비 사용)
                          InkWell(
                            onTap: _showRoundSelectionDialog,
                            child: Container(
                              width: double.infinity, // 전체 너비 사용
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade400),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween, // 양쪽 정렬
                                children: [
                                  // 선택된 라운드 정보
                                  Text(
                                    currentRoundDisplay,
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  // 드롭다운 아이콘
                                  const Icon(Icons.arrow_drop_down),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // 랭킹 리스트 컨테이너
                          Container(
                            height: MediaQuery.of(context).size.height * 0.3,
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ref
                                .watch(topRankingsProvider)
                                .when(
                                  loading:
                                      () => const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                  error: (error, stackTrace) {
                                    debugPrint("[HomeView] 랭킹 로드 에러: $error");
                                    return Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Text('랭킹을 불러올 수 없습니다.'),
                                          const SizedBox(height: 8),
                                          Text(
                                            '$error',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          ElevatedButton(
                                            onPressed: () {
                                              ref.invalidate(
                                                topRankingsProvider,
                                              );
                                            },
                                            child: const Text('다시 시도'),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  data: (List<RankEntry> rankings) {
                                    debugPrint(
                                      "[HomeView] 랭킹 로드됨: ${rankings.length}개",
                                    );
                                    if (rankings.isEmpty) {
                                      return const Center(
                                        child: Text(
                                          '아직 랭킹 데이터가 없습니다.\n게임을 플레이하여 랭킹에 등록해보세요!',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      );
                                    }
                                    return ListView.separated(
                                      itemCount: rankings.length,
                                      itemBuilder: (context, index) {
                                        final entry = rankings[index];
                                        return ListTile(
                                          dense: true,
                                          leading: Text(
                                            '${index + 1}',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          title: Text(entry.nick),
                                          trailing: Text(
                                            '${entry.score} 점',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        );
                                      },
                                      separatorBuilder:
                                          (context, index) => const Divider(
                                            height: 1,
                                            thickness: 1,
                                          ),
                                    );
                                  },
                                ),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.keyboard_arrow_right),
                        label: const Text('로비 가기'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          textStyle: Theme.of(context).textTheme.titleMedium,
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const LobbyView(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
    );
  }
}
