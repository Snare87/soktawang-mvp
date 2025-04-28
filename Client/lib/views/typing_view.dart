import 'dart:async'; // Timer 사용 위해 import

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// --- Providers ---

// 1. 사용자 입력을 저장하는 Provider
final currentInputProvider = StateProvider<String>((ref) {
  return ''; // 초기값은 빈 문자열
});

// 2. 게임 타이머 상태 정의 클래스
@immutable // 불변 객체로 만들기
class GameTimerState {
  final int remainingSeconds;
  final bool isActive;

  const GameTimerState({
    required this.remainingSeconds,
    required this.isActive,
  });
}

// 3. 게임 타이머 로직을 관리하는 StateNotifier
class GameTimerNotifier extends StateNotifier<GameTimerState> {
  GameTimerNotifier()
    : super(
        const GameTimerState(remainingSeconds: 60, isActive: false),
      ); // 초기 상태: 60초, 비활성

  Timer? _timer; // Timer 객체를 저장할 변수

  void startTimer() {
    if (state.isActive || state.remainingSeconds == 0) return;
    state = GameTimerState(
      remainingSeconds: state.remainingSeconds,
      isActive: true,
    );

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.remainingSeconds > 0) {
        state = GameTimerState(
          remainingSeconds: state.remainingSeconds - 1,
          isActive: true,
        );
      } else {
        // 시간이 0초가 되면 타이머 중지 (팝업 호출은 UI에서 ref.listen으로 처리)
        stopTimer();
        // print('DEBUG: GAME OVER - Time is up!'); // <-- UI에서 감지하므로 여기서 print 제거
      }
    });
  }

  void stopTimer() {
    _timer?.cancel();
    // 타이머가 멈출 때도 상태는 반영해야 함 (listen 콜백이 실행되도록)
    if (state.isActive) {
      // 활성 상태일 때만 비활성으로 변경
      state = GameTimerState(
        remainingSeconds: state.remainingSeconds,
        isActive: false,
      );
    }
  }

  // TODO: 필요시 게임 재시작을 위한 resetTimer() 구현
  // void resetTimer() {
  //   stopTimer();
  //   state = const GameTimerState(remainingSeconds: 60, isActive: false);
  //   // currentInputProvider도 리셋 필요: ref.read(currentInputProvider.notifier).state = '';
  // }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// 4. GameTimerNotifier를 제공하는 StateNotifierProvider
final gameTimerProvider =
    StateNotifierProvider<GameTimerNotifier, GameTimerState>((ref) {
      return GameTimerNotifier();
    });

// --- TypingView Widget ---

class TypingView extends ConsumerWidget {
  const TypingView({super.key});

  // --- 결과 팝업 표시 함수 ---
  void _showResultPopup(BuildContext context, WidgetRef ref) {
    // 게임 종료 시점의 최종 상태 읽기 (read 사용)
    final String finalInput = ref.read(currentInputProvider);
    final GameTimerState finalTimerState = ref.read(gameTimerProvider);
    // TODO: sampleSentence를 실제 게임 문장으로 교체 필요
    const String sampleSentence = "빠른 갈색 여우가 게으른 개를 뛰어 넘습니다.";

    // --- 최종 WPM, 정확도, 점수, 포인트 계산 ---
    final int totalTyped = finalInput.length;
    int correctlyTyped = 0;
    for (int i = 0; i < totalTyped; i++) {
      if (i < sampleSentence.length && sampleSentence[i] == finalInput[i]) {
        correctlyTyped++;
      }
    }
    final int elapsedTimeInSeconds = 60 - finalTimerState.remainingSeconds;
    double wpm = 0;
    if (elapsedTimeInSeconds > 0) {
      double elapsedTimeInMinutes = elapsedTimeInSeconds / 60.0;
      wpm = (correctlyTyped / 5) / elapsedTimeInMinutes;
    } else if (totalTyped > 0 && finalInput == sampleSentence) {
      // 시간이 0되기 직전 완료 시 처리 (선택적)
    }

    double accuracy = 0;
    if (totalTyped > 0) {
      accuracy = (correctlyTyped / totalTyped) * 100;
    }
    // TODO: 실제 점수 및 포인트 계산 로직 적용 필요
    final int score = (wpm * accuracy / 100 * 10).toInt(); // 임시 점수 계산
    final int points = (score / 5).toInt(); // 임시 포인트 계산

    // --- Dialog 표시 ---
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('🎉 게임 결과 🎉'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('타수: ${wpm.toInt()} WPM'),
                Text('정확도: ${accuracy.toStringAsFixed(1)}%'),
                const SizedBox(height: 16),
                Text(
                  '점수: $score 점',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '획득 포인트: $points P',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: '공유하기',
              onPressed: () {
                // TODO: 공유 기능 구현
                print('Share button pressed!');
              },
            ),
            TextButton(
              child: const Text('확인'),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // 팝업 닫기
                // TODO: 팝업 닫은 후 다음 행동 정의 (예: 상태 초기화, 화면 이동)
                // 예시: ref.invalidate(currentInputProvider);
                //       ref.read(gameTimerProvider.notifier).resetTimer(); // resetTimer 구현 필요
              },
            ),
          ],
        );
      },
    );
  }
  // --- _showResultPopup 함수 끝 ---

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // --- ref.listen: 타이머 상태 변경 감지하여 시간 종료 시 팝업 호출 ---
    ref.listen<GameTimerState>(gameTimerProvider, (previousState, newState) {
      // 상태가 '활성'에서 '비활성'으로 바뀌고, 남은 시간이 0일 때 (시간 종료 시)
      // previousState가 null일 수 있으므로 null safety 체크 추가 (?.)
      if (previousState?.isActive == true &&
          !newState.isActive &&
          newState.remainingSeconds == 0) {
        _showResultPopup(context, ref); // 시간 종료 시 팝업 호출
      }
    });
    // --- ref.listen 끝 ---

    // Provider들로부터 현재 상태 읽기 (watch 사용)
    final String currentInput = ref.watch(currentInputProvider);
    final GameTimerState timerState = ref.watch(gameTimerProvider);

    // TODO: sampleSentence를 실제 게임 문장으로 교체 필요
    const String sampleSentence = "빠른 갈색 여우가 게으른 개를 뛰어 넘습니다.";

    // --- RichText 생성을 위한 로직 ---
    List<TextSpan> textSpans = [];
    for (int i = 0; i < sampleSentence.length; i++) {
      TextStyle currentStyle;
      if (i < currentInput.length) {
        if (sampleSentence[i] == currentInput[i]) {
          // 맞은 글자
          currentStyle = const TextStyle(
            fontSize: 24,
            height: 1.5,
            letterSpacing: 1.2,
            color: Colors.green,
            fontWeight: FontWeight.bold,
          );
        } else {
          // 틀린 글자
          currentStyle = const TextStyle(
            fontSize: 24,
            height: 1.5,
            letterSpacing: 1.2,
            color: Colors.red,
            decoration: TextDecoration.lineThrough,
            decorationColor: Colors.red,
          );
        }
      } else {
        // 아직 입력되지 않은 글자
        currentStyle = TextStyle(
          fontSize: 24,
          height: 1.5,
          letterSpacing: 1.2,
          color: Colors.grey[400],
        );
      }
      textSpans.add(TextSpan(text: sampleSentence[i], style: currentStyle));
    }
    // --- TextSpan 로직 끝 ---

    // --- WPM 및 정확도 계산 로직 ---
    final int totalTyped = currentInput.length;
    int correctlyTyped = 0;
    for (int i = 0; i < totalTyped; i++) {
      if (i < sampleSentence.length && sampleSentence[i] == currentInput[i]) {
        correctlyTyped++;
      }
    }
    final int elapsedTimeInSeconds = 60 - timerState.remainingSeconds;
    double wpm = 0;
    if (elapsedTimeInSeconds > 0 && timerState.isActive) {
      // 타이머 활성화 중일 때만 계산
      double elapsedTimeInMinutes = elapsedTimeInSeconds / 60.0;
      wpm = (correctlyTyped / 5) / elapsedTimeInMinutes;
    }
    double accuracy = 0;
    if (totalTyped > 0) {
      accuracy = (correctlyTyped / totalTyped) * 100;
    }
    // --- 계산 로직 끝 ---

    return Scaffold(
      appBar: AppBar(title: const Text('타자 경기')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 상단 정보 Row (WPM, 정확도 표시)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '남은 시간: ${timerState.remainingSeconds}초',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '타수: ${wpm.toInt()} WPM',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '정확도: ${accuracy.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // 문제 문장 표시 영역 (RichText 사용)
            Container(
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withAlpha(26),
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: RichText(
                text: TextSpan(children: textSpans),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 32),

            // 사용자 입력 필드
            TextField(
              decoration: InputDecoration(
                hintText: '여기에 타자 입력...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              style: const TextStyle(fontSize: 18),
              onChanged: (newValue) {
                // 현재 타이머 상태 읽기
                final bool timerCurrentlyActive =
                    ref.read(gameTimerProvider).isActive;
                // 첫 글자 입력 시 타이머 시작
                if (!timerCurrentlyActive &&
                    newValue.isNotEmpty &&
                    ref.read(gameTimerProvider).remainingSeconds > 0) {
                  // 시간이 남아있을때만 시작
                  ref.read(gameTimerProvider.notifier).startTimer();
                }
                // 입력값 Provider 업데이트
                ref.read(currentInputProvider.notifier).state = newValue;
                // 문장 완성 체크
                if (newValue == sampleSentence) {
                  ref
                      .read(gameTimerProvider.notifier)
                      .stopTimer(); // 문장 완성 시 타이머 중지
                  _showResultPopup(context, ref); // 팝업 함수 호출
                }
              },
            ),

            const SizedBox(height: 24),

            // 입력 확인용 임시 텍스트
            Text(
              '입력 확인: $currentInput',
              style: const TextStyle(fontSize: 16, color: Colors.blueGrey),
            ),
          ],
        ),
      ),
    );
  }
}
