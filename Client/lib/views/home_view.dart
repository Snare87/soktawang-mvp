import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/home_providers.dart';
import '../providers/ranking_provider.dart';
import 'lobby_view.dart';
import '../services/notification_service.dart';
import '../providers/round_alarm_scheduler_provider.dart';

class HomeView extends ConsumerStatefulWidget {
  // ConsumerStatefulWidget으로 유지
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
    // View가 빌드된 후 첫 프레임이 렌더링된 다음에 실행됩니다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 현재 알람 설정 상태를 읽어옵니다.
      final bool alarmsCurrentlyEnabled = ref.read(alarmSettingsProvider);
      if (alarmsCurrentlyEnabled) {
        // 알람이 켜져 있다면, 다음 라운드 알람들을 스케줄링합니다.
        ref
            .read(roundAlarmSchedulerProvider)
            .refreshAlarms()
            .then((_) {
              print('[HomeView] initState: 다음 알람 세트 스케줄링 시도 완료.');
            })
            .catchError((e) {
              print('[HomeView] initState: 알람 스케줄링 중 오류: $e');
            });
      } else {
        print('[HomeView] initState: 알람이 꺼져있어 스케줄링하지 않음.');
      }
    });
  }

  // ... (dispose, _initializeOrResetTimer, formatDuration 메소드는 이전과 동일) ...
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _initializeOrResetTimer(Duration newRemainingTime) {
    if (newRemainingTime.inDays > 900) {
      // print("[HomeView] Timer not started, provider is loading.");
      _timer?.cancel();
      if (mounted) {
        setState(() {
          _currentRemainingTime = newRemainingTime;
        });
      }
      return;
    }

    // print("[HomeView] Initializing/Resetting timer with duration: $newRemainingTime");
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
          // print("[HomeView] Timer finished!");
          if (mounted) {
            setState(() {
              _currentRemainingTime = Duration.zero;
            });
            // 중요: 한 라운드가 끝나고 다음 라운드로 넘어갈 때 (타이머가 0이 될 때)
            // 알람 설정을 다시 확인하고 다음 알람들을 스케줄링합니다.
            // 이렇게 하면 앱을 계속 켜놓고 있는 사용자도 다음 라운드 알람을 받게 됩니다.
            final bool alarmsCurrentlyEnabled = ref.read(alarmSettingsProvider);
            if (alarmsCurrentlyEnabled) {
              ref
                  .read(roundAlarmSchedulerProvider)
                  .refreshAlarms()
                  .then((_) {
                    print('[HomeView] 라운드 전환: 다음 알람 세트 스케줄링 시도 완료.');
                  })
                  .catchError((e) {
                    print('[HomeView] 라운드 전환 중 알람 스케줄링 오류: $e');
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

  @override
  Widget build(BuildContext context) {
    final int freePlays = ref.watch(freePlaysProvider);

    ref.listen<Duration>(nextAlarmTimeProvider, (
      previousDuration,
      newDuration,
    ) {
      // print("[HomeView] nextAlarmTimeProvider changed: $newDuration");
      if (newDuration.inDays > 900 && _isTimerInitializedByProvider) {
        // print("[HomeView] Ignoring provider loading state after initial setup.");
        return;
      }
      _initializeOrResetTimer(newDuration);
      if (!(newDuration.inDays > 900)) {
        _isTimerInitializedByProvider = true;
      }
    });

    final String formattedTime = formatDuration(_currentRemainingTime);
    final isAlarmOn = ref.watch(alarmSettingsProvider); // AppBar 아이콘 업데이트용

    return Scaffold(
      appBar: AppBar(
        title: const Text('속타왕 홈'),
        automaticallyImplyLeading: false,
        actions: [
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
                  // Switch는 Consumer로 감싸서 자체적으로 rebuild되도록 합니다.
                  builder: (context, ref, child) {
                    final bool currentAlarmState = ref.watch(
                      alarmSettingsProvider,
                    );
                    return Switch(
                      value: currentAlarmState,
                      onChanged: (bool value) {
                        ref
                            .read(alarmSettingsProvider.notifier)
                            .setAlarmEnabled(value)
                            .then((_) {
                              // 상태 변경 후 SnackBar 표시
                              ScaffoldMessenger.of(
                                context,
                              ).removeCurrentSnackBar(); // 이전 SnackBar가 있다면 제거
                              if (value) {
                                // 알람을 켰을 때: 다음 라운드 알람을 스케줄링
                                ref
                                    .read(roundAlarmSchedulerProvider)
                                    .refreshAlarms()
                                    .then((_) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            '라운드 알림이 켜졌습니다. 다음 라운드부터 알림이 예약됩니다.',
                                          ),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    })
                                    .catchError((e) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text('알림 예약 중 오류: $e'),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    });
                              } else {
                                // 알람을 껐을 때: 예약된 모든 알림 취소
                                ref
                                    .read(notificationServiceProvider)
                                    .cancelAllNotifications();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      '라운드 알림이 꺼졌습니다. 예약된 모든 알림이 취소됩니다.',
                                    ),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            });
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
        // 기존 UI 구조 유지
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
                ],
              ),
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
