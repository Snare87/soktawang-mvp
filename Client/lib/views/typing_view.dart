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
    // 이미 타이머가 활성 상태이거나 남은 시간이 0이면 시작하지 않음
    if (state.isActive || state.remainingSeconds == 0) return;

    // 상태를 '활성'으로 변경하고 타이머 시작
    state = GameTimerState(
      remainingSeconds: state.remainingSeconds,
      isActive: true,
    );

    _timer?.cancel(); // 혹시 모를 기존 타이머 취소
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.remainingSeconds > 0) {
        // 남은 시간이 있으면 1초씩 감소
        state = GameTimerState(
          remainingSeconds: state.remainingSeconds - 1,
          isActive: true,
        );
      } else {
        // 남은 시간이 0이 되면 타이머 중지
        stopTimer();
        // TODO: 시간이 종료되었을 때의 로직 처리 (예: 결과 화면 표시)
      }
    });
  }

  void stopTimer() {
    _timer?.cancel(); // 타이머 취소
    // 상태를 '비활성'으로 변경 (남은 시간은 그대로 유지)
    state = GameTimerState(
      remainingSeconds: state.remainingSeconds,
      isActive: false,
    );
  }

  // TODO: 필요시 게임 재시작을 위한 resetTimer() 구현
  // void resetTimer() {
  //   stopTimer();
  //   state = const GameTimerState(remainingSeconds: 60, isActive: false);
  // }

  // StateNotifier가 더 이상 사용되지 않을 때 타이머를 확실히 취소 (메모리 누수 방지)
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO: 나중에는 실제 게임 문장을 받아와야 함
    const String sampleSentence = "빠른 갈색 여우가 게으른 개를 뛰어 넘습니다."; // 임시 샘플 문장

    // Provider들로부터 현재 상태 읽기 (watch 사용)
    final String currentInput = ref.watch(currentInputProvider);
    final GameTimerState timerState = ref.watch(gameTimerProvider);

    // --- RichText 생성을 위한 로직 (이전과 동일) ---
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
    final int totalTyped = currentInput.length; // 총 입력한 글자 수
    int correctlyTyped = 0; // 정확히 입력한 글자 수

    // 입력한 길이만큼 반복하며 정확히 입력한 글자 수 계산
    for (int i = 0; i < totalTyped; i++) {
      // sampleSentence 길이를 벗어나지 않는지 확인 (오타로 더 길게 입력 시 에러 방지)
      if (i < sampleSentence.length && sampleSentence[i] == currentInput[i]) {
        correctlyTyped++;
      }
    }

    // 경과 시간 계산 (타이머 시작 후)
    final int elapsedTimeInSeconds = 60 - timerState.remainingSeconds;
    double wpm = 0; // 분당 단어 수 (타수) 초기값

    // 경과 시간이 0보다 클 때만 WPM 계산 (0으로 나누기 방지)
    if (elapsedTimeInSeconds > 0 && timerState.isActive) {
      // 타이머가 활성화 되어 있을 때만 계산
      // 경과 시간을 분 단위로 변환 (소수점 포함)
      double elapsedTimeInMinutes = elapsedTimeInSeconds / 60.0;
      // WPM 계산 (5글자를 1단어로 간주)
      wpm = (correctlyTyped / 5) / elapsedTimeInMinutes;
    }

    // 정확도 계산 (0으로 나누기 방지)
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
            // 상단 정보 (시간, 타수 등)
            // 교체할 새로운 Row 코드
            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween, // 요소들을 양쪽 끝 공간에 분산 배치
              children: [
                // 남은 시간 표시
                Text(
                  '남은 시간: ${timerState.remainingSeconds}초', // 타이머 상태 사용
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ), // 글자 크기 약간 줄임
                ),
                // WPM(타수) 표시 (소수점 없이 정수로)
                Text(
                  '타수: ${wpm.toInt()} WPM', // 계산된 wpm 사용
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                // 정확도 표시 (소수점 한 자리까지)
                Text(
                  '정확도: ${accuracy.toStringAsFixed(1)}%', // 계산된 accuracy 사용
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            // 새로운 Row 코드 끝
            const SizedBox(height: 32),

            // 문제 문장 표시 영역 (RichText 사용) - 이전과 동일
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
                // 6. 첫 글자 입력 시 타이머 시작 로직 추가
                if (!timerState.isActive && newValue.isNotEmpty) {
                  // 타이머가 비활성 상태이고 입력값이 비어있지 않으면 타이머 시작
                  ref.read(gameTimerProvider.notifier).startTimer();
                }
                // 입력값 Provider 업데이트 (기존 로직)
                ref.read(currentInputProvider.notifier).state = newValue;
              },
            ),

            const SizedBox(height: 24),

            // 입력 확인용 임시 텍스트 - 그대로 둠 (나중에 필요 없으면 제거)
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
