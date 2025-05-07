import 'dart:async'; // Timer 사용 위해 import
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/home_providers.dart'; // Provider import
import '../providers/ranking_provider.dart'; // Ranking Provider import
import 'lobby_view.dart';

class HomeView extends ConsumerStatefulWidget {
  // ConsumerStatefulWidget으로 유지
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> {
  Timer? _timer; // 1초마다 실행될 타이머 객체
  Duration _currentRemainingTime = Duration.zero; // 화면에 표시될 현재 남은 시간 (State 변수)
  bool _isTimerInitializedByProvider =
      false; // Provider로부터 초기값을 받아 타이머를 시작했는지 여부

  @override
  void initState() {
    super.initState();
    // initState에서는 Provider를 직접 watch하기 어려우므로,
    // 첫 빌드 후 또는 listen 콜백에서 초기화합니다.
  }

  @override
  void dispose() {
    _timer?.cancel(); // 위젯이 화면에서 제거될 때 타이머 취소
    super.dispose();
  }

  void _initializeOrResetTimer(Duration newRemainingTime) {
    // Duration(days: 999)는 로딩 상태를 의미하므로 타이머 시작 안 함
    if (newRemainingTime.inDays > 900) {
      print("[HomeView] Timer not started, provider is loading.");
      _timer?.cancel(); // 기존 타이머가 있다면 중지
      if (mounted) {
        setState(() {
          _currentRemainingTime = newRemainingTime; // 화면에는 "--:--" 표시되도록
        });
      }
      return;
    }

    print(
      "[HomeView] Initializing/Resetting timer with duration: $newRemainingTime",
    );
    _timer?.cancel(); // 기존 타이머가 있다면 중지
    if (mounted) {
      // 위젯이 화면에 마운트된 상태인지 확인
      setState(() {
        _currentRemainingTime = newRemainingTime;
      });
    }

    if (_currentRemainingTime.inSeconds > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timerInstance) {
        if (_currentRemainingTime.inSeconds <= 0) {
          timerInstance.cancel();
          print("[HomeView] Timer finished!");
          // TODO: 시간이 0초가 되었을 때 처리
          if (mounted) {
            // 0초가 되었을 때도 화면 갱신
            setState(() {
              _currentRemainingTime = Duration.zero;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _currentRemainingTime =
                  _currentRemainingTime - const Duration(seconds: 1);
            });
          } else {
            // 위젯이 dispose된 후 타이머가 계속 실행되는 것을 방지
            timerInstance.cancel();
          }
        }
      });
    }
  }

  String formatDuration(Duration d) {
    if (d.inDays > 900) {
      // 로딩 중 값 처리
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

    // Provider의 값이 바뀔 때마다 타이머를 초기화/재시작하도록 listen
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('속타왕 홈'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        // <--- 여기 padding 파라미터!
        padding: const EdgeInsets.all(16.0), // 전체적인 여백 다시 추가
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // --- 상단 정보 영역 (무료 플레이, 다음 라운드 시간) ---
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
                // <--- 여기에 onPressed 와 label 파라미터!
                icon: const Icon(Icons.keyboard_arrow_right),
                label: const Text('로비 가기'), // label 추가
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  textStyle: Theme.of(context).textTheme.titleMedium,
                ),
                onPressed: () {
                  // onPressed 추가
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const LobbyView()),
                  );
                },
              ), // 로비 가기 버튼 끝
            ],
          ),
        ),
      ),
    );
  } // build 메소드 끝
}
