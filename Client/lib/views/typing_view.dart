import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // ← 추가
import 'package:cloud_functions/cloud_functions.dart';
import '../providers/game_providers.dart'; // Sentence providers
import '../providers/ranking_provider.dart';
import '../providers/round_provider.dart'; // currentRoundIdProvider, roundDocumentProvider

// --- Providers (Input & Timer) ---
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
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
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
    StateNotifierProvider<GameTimerNotifier, GameTimerState>(
      (_) => GameTimerNotifier(),
    );

// --- TypingView Widget ---
class TypingView extends ConsumerStatefulWidget {
  const TypingView({super.key});

  @override
  ConsumerState<TypingView> createState() => _TypingViewState();
}

// --- TypingView State ---
class _TypingViewState extends ConsumerState<TypingView> {
  bool _isResultSubmitting = false; // 결과 제출 중 플래그
  bool _shouldCloseAfterSubmit = false; // 제출 후 닫기 플래그

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startNewGame();
    });
  }

  /// <--- 여기부터 수정된 _startNewGame() 코드 전체 ↓
  Future<void> _startNewGame() async {
    debugPrint("🙏 _startNewGame 시작");
    _isResultSubmitting = false;
    try {
      // 1) 최신 Round ID 획득
      final rid = await joinRound();
      debugPrint("1) 받은 rid: $rid");

      if (!mounted) return;
      ref.read(currentRoundIdProvider.notifier).state = rid;

      // 2) Round 문서에서 sentenceId 조회
      final round = await ref.read(roundDocumentProvider.future);
      debugPrint("2) Round 문서: ${round.id}, sentenceId=${round.sentenceId}");

      // 3) sentences 컬렉션에서 실제 텍스트 한 건 조회
      final sentDoc =
          await FirebaseFirestore.instance
              .collection('sentences')
              .doc(round.sentenceId)
              .get();
      debugPrint("3) sentences 문서 존재여부: ${sentDoc.exists}");

      final sentData = sentDoc.data();
      if (sentData == null) throw Exception('문장 문서가 없습니다: ${round.sentenceId}');
      final String sentence = sentData['text'] as String;

      if (!mounted) return;
      // 4) 기존 currentGameSentenceProvider 대신 실제 문장 세팅
      ref.read(currentGameSentenceProvider.notifier).state = sentence;

      // 5) Input·Timer 초기화
      ref.invalidate(currentInputProvider);
      ref.invalidate(gameTimerProvider);

      _initializeTypingGame();

      debugPrint("New game started with sentence: $sentence");
    } catch (e) {
      debugPrint('게임 시작 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('게임 시작 실패: $e')));
      }
    }
  }

  /// <--- 수정된 _startNewGame() 끝

  void _initializeTypingGame() {
    // 이전 loadNewRandomSentence(ref); 대신 생략하거나 남길 수 있습니다.
  }

  // --- 비동기 작업 후 UI 업데이트를 위한 헬퍼 메서드 ---
  void _completeAndClose() {
    if (!mounted) return;
    setState(() {
      _isResultSubmitting = false;
      _shouldCloseAfterSubmit = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pop(); // 결과 팝업 닫기
    });
  }

  // --- 결과 팝업 표시 함수 ---
  void _showResultPopup() {
    final String finalInput = ref.read(currentInputProvider);
    final GameTimerState finalTimerState = ref.read(gameTimerProvider);
    final String gameSentence = ref.read(currentGameSentenceProvider);
    debugPrint("▶ build() gameSentence = '$gameSentence'");
    // 최종 WPM, 정확도 계산
    final int totalTyped = finalInput.length;
    int correctlyTyped = 0;
    for (int i = 0; i < totalTyped; i++) {
      if (i < gameSentence.length && gameSentence[i] == finalInput[i]) {
        correctlyTyped++;
      }
    }
    final int elapsedSec = 60 - finalTimerState.remainingSeconds;
    double wpm = 0;
    if (elapsedSec > 0) {
      wpm = (correctlyTyped / 5) / (elapsedSec / 60);
    }
    double accuracy = totalTyped > 0 ? (correctlyTyped / totalTyped) * 100 : 0;

    final int score = (wpm * accuracy / 100 * 10).toInt();
    final int points = (score / 5).toInt();

    showDialog(
      context: context,
      barrierDismissible: _isResultSubmitting ? false : true,
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
              onPressed:
                  _isResultSubmitting
                      ? null
                      : () {
                        debugPrint('Share button pressed!');
                      },
            ),
            _isResultSubmitting
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
                    if (_isResultSubmitting) return;
                    setState(() => _isResultSubmitting = true);

                    // 1) Provider에서 실제 값 꺼내기
                    final String roundId =
                        ref.read(currentRoundIdProvider)!; // 현재 라운드 ID
                    final round = await ref.read(
                      roundDocumentProvider.future,
                    ); // Round 객체 읽기
                    final String sentenceId =
                        round.sentenceId; // 라운드의 sentenceId

                    // 2) 전송할 데이터 맵 구성
                    final dataToSubmit = <String, dynamic>{
                      'score': score,
                      'wpm': wpm.toInt(),
                      'accuracy': accuracy,
                      'sentenceId': sentenceId,
                      'roundId': roundId,
                    };

                    try {
                      final functions = FirebaseFunctions.instanceFor(
                        region: 'asia-southeast1',
                      );
                      final callable = functions.httpsCallable('scoreSubmit');
                      await callable.call(dataToSubmit); // 실제 Map을 전달
                      debugPrint('DEBUG: scoreSubmit 완료: $dataToSubmit');
                    } catch (e) {
                      debugPrint('ERROR during function call: $e');
                    } finally {
                      _completeAndClose(); // 결과 팝업 및 화면 닫기
                    }
                  },
                ),
          ],
        );
      },
    );
  }

  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    final String currentInput = ref.watch(currentInputProvider);
    final GameTimerState timerState = ref.watch(gameTimerProvider);
    final String gameSentence = ref.watch(currentGameSentenceProvider);

    // 이전 포커스에서 팝업을 닫은 후 화면도 pop 해야 하는 경우
    if (_shouldCloseAfterSubmit) {
      _shouldCloseAfterSubmit = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }

    // 글자별 하이라이트를 위한 TextSpan 리스트 생성
    List<TextSpan> textSpans = [];
    for (int i = 0; i < gameSentence.length; i++) {
      final bool isTyped = i < currentInput.length;
      final bool isCorrect = isTyped && gameSentence[i] == currentInput[i];
      TextStyle style;
      if (isTyped) {
        style =
            isCorrect
                ? const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                )
                : const TextStyle(
                  color: Colors.red,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: Colors.red,
                );
      } else {
        style = TextStyle(color: Colors.grey.shade400);
      }
      textSpans.add(TextSpan(text: gameSentence[i], style: style));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('타자 경기')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1) 문장 하이라이트 영역
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 18, height: 1.5),
                  children: textSpans,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 32),

            // 2) **여기**가 빠져 있었던 TextField
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

            // 3) 디버그용 텍스트 (입력/타이머 상태 확인)
            Text(
              '입력 확인: $currentInput',
              style: const TextStyle(fontSize: 16, color: Colors.blueGrey),
            ),
            Text(
              '남은 시간: ${timerState.remainingSeconds}초',
              style: const TextStyle(fontSize: 16, color: Colors.blueGrey),
            ),

            // … 이하 계속 …
          ],
        ),
      ),
    );
  }
}
