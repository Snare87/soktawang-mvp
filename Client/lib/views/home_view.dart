import 'dart:async'; // Timer 사용 위해 import
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/home_providers.dart'; // Provider import
import '../providers/ranking_provider.dart'; // Ranking Provider import
import 'lobby_view.dart';
import '../services/notification_service.dart'; // << 이 줄 추가 (또는 올바른 경로로 수정)

class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> {
  Timer? _timer;
  Duration _currentRemainingTime = Duration.zero;
  bool _isTimerInitializedByProvider = false;

  @override
  void initState() {
    super.initState();
    // 앱 시작 시 또는 HomeView가 처음 빌드될 때 다음 라운드 알람 스케줄링 시도
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   // TODO: 다음 단계에서 만들 roundAlarmSchedulerProvider를 사용하여 알람 스케줄링
    //   // 예: ref.read(roundAlarmSchedulerProvider).scheduleNextSetOfAlarms();
    // });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _initializeOrResetTimer(Duration newRemainingTime) {
    if (newRemainingTime.inDays > 900) {
      print("[HomeView] Timer not started, provider is loading.");
      _timer?.cancel();
      if (mounted) {
        setState(() {
          _currentRemainingTime = newRemainingTime;
        });
      }
      return;
    }

    print(
      "[HomeView] Initializing/Resetting timer with duration: $newRemainingTime",
    );
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
          print("[HomeView] Timer finished!");
          if (mounted) {
            setState(() {
              _currentRemainingTime = Duration.zero;
            });
            // TODO: 타이머 종료 시 (다음 라운드 시작 시) 알람 재스케줄링 로직 호출 고려
            // 예: ref.read(roundAlarmSchedulerProvider).scheduleNextSetOfAlarms();
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

  @override
  Widget build(BuildContext context) {
    final int freePlays = ref.watch(freePlaysProvider);
    final Duration currentRemainingTimeFromProvider = ref.watch(
      nextAlarmTimeProvider,
    );

    ref.listen<Duration>(nextAlarmTimeProvider, (
      previousDuration,
      newDuration,
    ) {
      print("[HomeView] nextAlarmTimeProvider changed: $newDuration");
      if (newDuration.inDays > 900 && _isTimerInitializedByProvider) {
        print(
          "[HomeView] Ignoring provider loading state after initial setup.",
        );
        return;
      }
      _initializeOrResetTimer(newDuration);
      if (!(newDuration.inDays > 900)) {
        _isTimerInitializedByProvider = true;
      }
    });

    final String formattedTime = formatDuration(_currentRemainingTime);

    // 알람 설정 상태를 watch합니다.
    final isAlarmOn = ref.watch(alarmSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('속타왕 홈'),
        automaticallyImplyLeading: false, // 뒤로가기 버튼 숨김
        actions: [
          // AppBar 오른쪽에 알람 설정 아이콘과 텍스트 추가
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Row(
              children: [
                Icon(
                  isAlarmOn
                      ? Icons.notifications_active
                      : Icons.notifications_off_outlined,
                ),
                // Consumer를 사용하여 alarmSettingsProvider 상태에 따라 Switch를 빌드
                Consumer(
                  builder: (context, ref, child) {
                    final bool currentAlarmState = ref.watch(
                      alarmSettingsProvider,
                    );
                    return Switch(
                      value: currentAlarmState,
                      onChanged: (bool value) {
                        // Switch 상태가 변경되면 alarmSettingsProvider를 통해 상태 업데이트
                        ref
                            .read(alarmSettingsProvider.notifier)
                            .setAlarmEnabled(value);
                        if (value) {
                          // 알람을 켰을 때: 다음 라운드 알람을 스케줄링하는 로직 호출
                          // TODO: 다음 단계에서 만들 roundAlarmSchedulerProvider 사용
                          // 예시: ref.read(roundAlarmSchedulerProvider).scheduleNextSetOfAlarms();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                '라운드 알림이 켜졌습니다. 다음 라운드부터 알림이 예약됩니다.',
                              ),
                            ),
                          );
                        } else {
                          // 알람을 껐을 때: 예약된 모든 알림 취소
                          ref
                              .read(notificationServiceProvider)
                              .cancelAllNotifications();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('라운드 알림이 꺼졌습니다. 예약된 모든 알림이 취소됩니다.'),
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ... (기존 '남은 무료 플레이', '다음 라운드까지' Text 위젯들) ...
              Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.local_activity_outlined, size: 20),
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
                  // --- 알람 설정 스위치 (SwitchListTile 사용 예시) ---
                  // Consumer를 사용하여 alarmSettingsProvider 상태에 따라 SwitchListTile을 빌드
                  // AppBar에 넣었으므로 여기서는 주석 처리하거나 다른 위치에 둘 수 있습니다.
                  // Consumer(
                  //   builder: (context, ref, child) {
                  //     final bool isAlarmEnabled = ref.watch(alarmSettingsProvider);
                  //     return SwitchListTile(
                  //       title: const Text('라운드 알림 받기'),
                  //       value: isAlarmEnabled,
                  //       onChanged: (bool value) {
                  //         ref.read(alarmSettingsProvider.notifier).setAlarmEnabled(value);
                  //         if (value) {
                  //           // 알람 ON 시 로직 (예: 다음 알람 스케줄링)
                  //           // ref.read(roundAlarmSchedulerProvider).scheduleNextSetOfAlarms();
                  //           ScaffoldMessenger.of(context).showSnackBar(
                  //             const SnackBar(content: Text('라운드 알림이 켜졌습니다.')),
                  //           );
                  //         } else {
                  //           // 알람 OFF 시 로직 (예: 모든 알람 취소)
                  //           ref.read(notificationServiceProvider).cancelAllNotifications();
                  //           ScaffoldMessenger.of(context).showSnackBar(
                  //             const SnackBar(content: Text('라운드 알림이 꺼졌습니다.')),
                  //           );
                  //         }
                  //       },
                  //     );
                  //   },
                  // ),
                ],
              ),

              // --- 중간: 실시간 랭킹 표시 영역 ---
              Column(
                children: [
                  Text(
                    '🏆 실시간 Top 10',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
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
                            print(
                              "Error in topRankingsProvider: $error\n$stackTrace",
                            );
                            return Center(
                              child: Text('랭킹을 불러올 수 없습니다.\n$error'),
                            );
                          },
                          data: (List<RankEntry> rankings) {
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
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
                                  (context, index) =>
                                      const Divider(height: 1, thickness: 1),
                            );
                          },
                        ),
                  ),
                ],
              ), // 랭킹 영역 끝
              // --- 하단: 로비 가기 버튼 ---
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
                    MaterialPageRoute(builder: (context) => const LobbyView()),
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
