import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart'; // kIsWeb
import 'package:firebase_auth/firebase_auth.dart'; // Auth import
import '../providers/game_providers.dart'; // Sentence providers
import '../providers/ranking_provider.dart'; // currentRoundIdProvider import

// --- Providers (Input & Timer - State specific to this view) ---
final currentInputProvider = StateProvider<String>((_) => '');

@immutable
class GameTimerState {
  final int remainingSeconds;
  final bool isActive;
  const GameTimerState({
    required this.remainingSeconds,
    required this.isActive,
  });
}

class GameTimerNotifier extends StateNotifier<GameTimerState> {
  GameTimerNotifier()
    : super(const GameTimerState(remainingSeconds: 60, isActive: false));
  Timer? _timer;

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
        stopTimer();
      }
    });
  }

  void stopTimer() {
    _timer?.cancel();
    if (state.isActive) {
      state = GameTimerState(
        remainingSeconds: state.remainingSeconds,
        isActive: false,
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final gameTimerProvider =
    StateNotifierProvider<GameTimerNotifier, GameTimerState>((ref) {
      return GameTimerNotifier();
    });

// --- TypingView Widget ---
class TypingView extends ConsumerStatefulWidget {
  const TypingView({super.key});

  @override
  ConsumerState<TypingView> createState() => _TypingViewState();
}

// --- TypingView State ---
class _TypingViewState extends ConsumerState<TypingView> {
  bool _isResultSubmitting = false; // <--- 결과 제출 중 상태 플래그

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _startNewGame();
      }
    });
  }

  void _startNewGame() {
    _isResultSubmitting = false; // <--- 플래그 초기화 추가
    loadNewRandomSentence(ref);
    ref.invalidate(currentInputProvider);
    ref.invalidate(gameTimerProvider);
    print("New game started!");
  }

  // --- 결과 팝업 표시 함수 (State 클래스 내부) ---
  void _showResultPopup() {
    final String finalInput = ref.read(currentInputProvider);
    final GameTimerState finalTimerState = ref.read(gameTimerProvider);
    final String gameSentence = ref.read(currentGameSentenceProvider);

    // --- 최종 WPM, 정확도 등 계산 ---
    final int totalTyped = finalInput.length;
    int correctlyTyped = 0;
    for (int i = 0; i < totalTyped; i++) {
      if (i < gameSentence.length && gameSentence[i] == finalInput[i])
        correctlyTyped++;
    }
    final int elapsedTimeInSeconds = 60 - finalTimerState.remainingSeconds;
    double wpm = 0;
    if (elapsedTimeInSeconds > 0) {
      double elapsedMinutes = elapsedTimeInSeconds / 60.0;
      wpm = (correctlyTyped / 5) / elapsedMinutes;
    } else if (totalTyped > 0 &&
        finalInput == gameSentence &&
        !finalTimerState.isActive) {
      /* Edge case handling (optional) */
    }
    double accuracy = 0;
    if (totalTyped > 0) {
      accuracy = (correctlyTyped / totalTyped) * 100;
    }
    final int score = (wpm * accuracy / 100 * 10).toInt();
    final int points = (score / 5).toInt();

    showDialog(
      context: context, // State의 context 사용
      barrierDismissible: _isResultSubmitting ? false : true, // 제출 중 닫기 방지
      builder: (BuildContext dialogContext) {
        // AlertDialog는 Stateless. 버튼 상태는 State 클래스의 _isResultSubmitting으로 제어
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
              onPressed:
                  _isResultSubmitting
                      ? null
                      : () {
                        print('Share button pressed!');
                      }, // State 변수 확인
            ),
            // 확인 버튼 또는 로딩 표시
            _isResultSubmitting // State 변수 확인
                ? const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 8.0,
                  ),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
                : TextButton(
                  child: const Text('확인'),
                  onPressed: () async {
                    // --- 중복 호출 방지 강화 ---
                    if (_isResultSubmitting) return; // 이미 제출 중이면 무시

                    // 제출 시작: State 변수 변경 및 UI 업데이트 요청 (setState 호출)
                    setState(() {
                      _isResultSubmitting = true;
                    });

                    // --- 함수 호출 로직 ---
                    print(
                      "Current User UID before call: ${FirebaseAuth.instance.currentUser?.uid}",
                    );
                    final Map<String, dynamic> dataToSubmit = {
                      'score': score, 'wpm': wpm.toInt(), 'accuracy': accuracy,
                      'sentenceId': 'sentence_id_placeholder', // TODO
                      'roundId': ref.read(
                        currentRoundIdProvider,
                      ), // Provider에서 읽기
                    };
                    print(
                      'DEBUG: Calling scoreSubmit with data: $dataToSubmit',
                    );
                    try {
                      FirebaseFunctions functions = FirebaseFunctions.instance;
                      final callable = functions.httpsCallable('scoreSubmit');
                      final HttpsCallableResult result = await callable.call(
                        dataToSubmit,
                      );
                      print(
                        'DEBUG: scoreSubmit function completed successfully.',
                      );
                      print('DEBUG: Result data: ${result.data}');
                    } catch (e) {
                      print('ERROR during function call: $e');
                      // 에러 발생 시 버튼 다시 활성화 하려면 setState 필요
                      if (mounted)
                        setState(
                          () => _isResultSubmitting = false,
                        ); // 에러 시 버튼 복구
                    } finally {
                      // 팝업 닫기 (dialogContext 사용)
                      if (Navigator.of(dialogContext).canPop()) {
                        Navigator.of(dialogContext).pop();
                      }
                      // 이전 화면(LobbyView)으로 이동 (State의 context 사용)
                      // _isResultSubmitting은 finally 후에 실행될 수 있으므로 여기서 false로 바꾸면 안됨
                      // _startNewGame에서 false로 리셋됨
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) Navigator.of(context).pop();
                      });
                    }
                  }, // onPressed 끝
                ), // TextButton 끝
          ],
        );
      }, // showDialog builder 끝
    ); // showDialog 끝
  }
  // --- _showResultPopup 함수 끝 ---

  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    // 타이머 상태 변경 감지
    ref.listen<GameTimerState>(gameTimerProvider, (previousState, newState) {
      if (previousState?.isActive == true &&
          !newState.isActive &&
          newState.remainingSeconds == 0) {
        _showResultPopup();
      }
    });

    // Provider들 watch
    final String currentInput = ref.watch(currentInputProvider);
    final GameTimerState timerState = ref.watch(gameTimerProvider);
    final String gameSentence = ref.watch(currentGameSentenceProvider);

    // --- RichText Spans Logic ---
    List<TextSpan> textSpans = [];
    if (gameSentence.isNotEmpty) {
      for (int i = 0; i < gameSentence.length; i++) {
        TextStyle currentStyle;
        if (i < currentInput.length) {
          if (gameSentence[i] == currentInput[i]) {
            /* 맞음 */
            currentStyle = const TextStyle(
              fontSize: 24,
              height: 1.5,
              letterSpacing: 1.2,
              color: Colors.green,
              fontWeight: FontWeight.bold,
            );
          } else {
            /* 틀림 */
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
          /* 입력 안 됨 */
          currentStyle = TextStyle(
            fontSize: 24,
            height: 1.5,
            letterSpacing: 1.2,
            color: Colors.grey[400],
          );
        }
        textSpans.add(TextSpan(text: gameSentence[i], style: currentStyle));
      }
    }
    // --- TextSpan Logic End ---

    // --- WPM/Accuracy Calculation ---
    final int totalTyped = currentInput.length;
    int correctlyTyped = 0;
    for (int i = 0; i < totalTyped; i++) {
      if (i < gameSentence.length && gameSentence[i] == currentInput[i])
        correctlyTyped++;
    }
    final int elapsedTimeInSeconds = 60 - timerState.remainingSeconds;
    double wpm = 0;
    if (elapsedTimeInSeconds > 0 && timerState.isActive) {
      double elapsedMinutes = elapsedTimeInSeconds / 60.0;
      wpm = (correctlyTyped / 5) / elapsedMinutes;
    }
    double accuracy = 0;
    if (totalTyped > 0) {
      accuracy = (correctlyTyped / totalTyped) * 100;
    }
    // --- Calculation End ---

    return Scaffold(
      appBar: AppBar(title: const Text('타자 경기')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Row
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

            // Sentence Area
            Container(
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withAlpha(26),
                borderRadius: BorderRadius.circular(12.0),
              ),
              child:
                  gameSentence.isEmpty
                      ? const Center(
                        child: Text(
                          "문장 로딩 중...",
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                      : RichText(
                        text: TextSpan(children: textSpans),
                        textAlign: TextAlign.center,
                      ),
            ),
            const SizedBox(height: 32),

            // Input Field
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
                final bool timerCanStart =
                    !ref.read(gameTimerProvider).isActive &&
                    ref.read(gameTimerProvider).remainingSeconds > 0;
                if (timerCanStart && newValue.isNotEmpty) {
                  ref.read(gameTimerProvider.notifier).startTimer();
                }
                ref.read(currentInputProvider.notifier).state = newValue;
                if (gameSentence.isNotEmpty && newValue == gameSentence) {
                  if (ref.read(gameTimerProvider).isActive) {
                    ref.read(gameTimerProvider.notifier).stopTimer();
                    _showResultPopup();
                  }
                }
              },
            ),
            const SizedBox(height: 24),

            // Debug Text
            Text(
              '입력 확인: $currentInput',
              style: const TextStyle(fontSize: 16, color: Colors.blueGrey),
            ),
          ],
        ),
      ),
    );
  } // build Method End
} // _TypingViewState Class End
