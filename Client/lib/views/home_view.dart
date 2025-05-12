import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/home_providers.dart';
import '../providers/ranking_provider.dart';
import 'lobby_view.dart';
import '../services/notification_service.dart';
import '../providers/round_alarm_scheduler_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/round_provider.dart';

// 선택한 라운드 ID 상태를 관리하는 Provider
final selectedRoundIdProvider = StateProvider<String?>((ref) {
  return ref.watch(rankingRoundIdProvider);
});

// 라운드 목록을 가져오는 Provider
final roundListProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return FirebaseFirestore.instance
      .collection('rounds')
      .orderBy('startAt', descending: true)
      .limit(20) // 최근 20개 라운드만 표시
      .snapshots()
      .map((snapshot) {
        return snapshot.docs.map((doc) {
          final data = doc.data();
          final startAt = data['startAt'] as Timestamp;
          // 라운드 시작 시간을 읽기 쉬운 형식으로 변환 (MM/DD HH:MM)
          final startDate = startAt.toDate();
          final formattedDate =
              '${startDate.month}/${startDate.day} ${startDate.hour.toString().padLeft(2, '0')}:${startDate.minute.toString().padLeft(2, '0')}';

          return {
            'id': doc.id,
            'label':
                '라운드 #${doc.id.substring(doc.id.length - 4)} ($formattedDate)',
            'startAt': startAt,
          };
        }).toList();
      });
});

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

    debugPrint(
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
          debugPrint("[HomeView] Timer finished! Refreshing round data...");
          if (mounted) {
            setState(() {
              _currentRemainingTime = Duration.zero;
            });

            // 타이머가 끝났을 때 다음 라운드 정보를 강제로 새로고침
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                // ignore: unused_result
                ref.refresh(nextAvailableRoundProvider);
              }
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

  @override
  Widget build(BuildContext context) {
    final int freePlays = ref.watch(freePlaysProvider);

    // 다음 참가 마감까지 남은 시간 확인 (10분 카운트다운)
    ref.listen<Duration>(nextEntryCloseTimeProvider, (
      previousDuration,
      newDuration,
    ) {
      debugPrint("[HomeView] nextEntryCloseTimeProvider changed: $newDuration");
      if (newDuration.inDays > 900 && _isTimerInitializedByProvider) {
        debugPrint(
          "[HomeView] Ignoring provider loading state after initial setup.",
        );
        return;
      }
      _initializeOrResetTimer(newDuration);
      if (!(newDuration.inDays > 900)) {
        _isTimerInitializedByProvider = true;
      }
    });

    final String formattedEntryCloseTime = formatDuration(
      _currentRemainingTime,
    );
    final isAlarmOn = ref.watch(alarmSettingsProvider);

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
                _buildAlarmSwitch(),
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
                        '이번 라운드 참가 마감까지: $formattedEntryCloseTime',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ],
              ),
              Column(
                children: [
                  // 여기가 변경될 부분입니다. Row를 Column으로 수정
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🏆 라운드별 랭킹 확인',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildRoundDropdown(),
                    ],
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
                    child: _buildRankingsList(),
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

  // 라운드 드롭다운 위젯
  // 라운드 드롭다운 위젯
  Widget _buildRoundDropdown() {
    return ref
        .watch(roundListProvider)
        .when(
          loading:
              () => const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          error: (err, stack) => Text('오류: $err'),
          data: (rounds) {
            if (rounds.isEmpty) {
              return const Text('라운드 정보 없음');
            }

            // 현재 선택된 라운드 ID
            final currentSelectedId = ref.watch(selectedRoundIdProvider);

            // 드롭다운 목록에 현재 선택된 ID가 없으면 빌드 후에 첫 번째 항목 선택
            if (currentSelectedId == null ||
                !rounds.any((round) => round['id'] == currentSelectedId)) {
              // 디버깅 로그
              debugPrint(
                "Selected round ID not in list, will update to first item: ${rounds[0]['id']}",
              );

              // 빌드 후에 상태 업데이트
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  ref.read(selectedRoundIdProvider.notifier).state =
                      rounds[0]['id'];
                }
              });

              // 첫 번째 항목으로 임시 표시
              return DropdownButton<String>(
                value: rounds[0]['id'],
                onChanged: (newValue) {
                  if (newValue != null) {
                    ref.read(selectedRoundIdProvider.notifier).state = newValue;
                    debugPrint("Selected round changed to: $newValue");
                  }
                },
                items:
                    rounds.map<DropdownMenuItem<String>>((round) {
                      return DropdownMenuItem<String>(
                        value: round['id'],
                        child: Text(round['label']),
                      );
                    }).toList(),
              );
            }

            // 정상적인 경우: 현재 선택된 ID로 드롭다운 표시
            return DropdownButton<String>(
              value: currentSelectedId,
              onChanged: (newValue) {
                if (newValue != null) {
                  ref.read(rankingRoundIdProvider.notifier).state = newValue;
                  debugPrint("Selected ranking round changed to: $newValue");
                }
              },
              items:
                  rounds.map<DropdownMenuItem<String>>((round) {
                    return DropdownMenuItem<String>(
                      value: round['id'],
                      child: Text(round['label']),
                    );
                  }).toList(),
            );
          },
        );
  }

  // 랭킹 리스트 위젯
  Widget _buildRankingsList() {
    // 현재 선택된 라운드 ID
    final selectedRoundId = ref.watch(selectedRoundIdProvider);
    final currentRoundId = ref.watch(gameRoundIdProvider);

    // 선택된 라운드 ID가 현재 라운드 ID와 다르면 빌드 후에 업데이트
    if (selectedRoundId != ref.read(rankingRoundIdProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(gameRoundIdProvider.notifier).state = selectedRoundId;
      });
    }

    // 해당 라운드의 랭킹 데이터를 가져옴
    return ref
        .watch(topRankingsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) {
            debugPrint("Error loading rankings: $error");
            return Center(child: Text('랭킹을 불러올 수 없습니다.\n$error'));
          },
          data: (rankings) {
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  title: Text(entry.nick),
                  trailing: Text(
                    '${entry.score} 점',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                );
              },
              separatorBuilder:
                  (context, index) => const Divider(height: 1, thickness: 1),
            );
          },
        );
  }

  // 알람 스위치 빌드 메서드 - 별도의 클래스 대신 메서드로 구현
  Widget _buildAlarmSwitch() {
    final bool currentAlarmState = ref.watch(alarmSettingsProvider);

    return Switch(
      value: currentAlarmState,
      onChanged: (bool value) {
        // 비동기 코드에서 직접 BuildContext를 사용하지 않도록 수정
        // 1. 먼저 값을 저장
        ref.read(alarmSettingsProvider.notifier).setAlarmEnabled(value);

        // 2. 즉시 현재 BuildContext를 사용하여 SnackBar 취소 및 메시지 표시
        final scaffoldMessenger = ScaffoldMessenger.of(context);
        scaffoldMessenger.removeCurrentSnackBar();

        // 3. 값에 따라 다른 작업 수행
        if (value) {
          // On: 알람 스케줄링 후 결과 처리
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('라운드 알림 켜는 중...'),
              duration: Duration(seconds: 1),
            ),
          );

          ref
              .read(roundAlarmSchedulerProvider)
              .refreshAlarms()
              .then((_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('라운드 알림이 켜졌습니다. 다음 라운드부터 알림이 예약됩니다.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              })
              .catchError((e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('알림 예약 중 오류: $e'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              });
        } else {
          // Off: 알람 취소
          ref.read(notificationServiceProvider).cancelAllNotifications();
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('라운드 알림이 꺼졌습니다. 예약된 모든 알림이 취소됩니다.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      },
    );
  }
}
