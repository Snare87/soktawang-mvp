// client/lib/providers/game_providers.dart
import 'dart:math'; // Random 사용 위해 import
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/sentences.dart'; // 방금 만든 문장 데이터 import
import 'package:flutter/foundation.dart';

/// 전체 연습 문장 리스트를 제공하는 Provider
final sentenceListProvider = Provider<List<String>>((ref) {
  // 실제 앱에서는 여기서 파일을 읽거나 DB에서 가져올 수 있습니다.
  return practiceSentences;
});

/// 현재 게임에 사용될 문장을 관리하는 StateProvider
/// 외부에서 상태를 직접 변경할 수 있도록 .notifier 와 .state 를 사용합니다.
final currentGameSentenceProvider = StateProvider<String>((ref) {
  // 초기값은 비워둠. 게임 시작 시 업데이트됨.
  return '';
});

/// 게임 시작 시 새로운 랜덤 문장을 로드하는 함수 (Provider 내부에 넣어도 되지만 편의상 분리)
/// 이 함수는 외부(예: TypingView)에서 ref를 전달받아 호출됩니다.
void loadNewRandomSentence(WidgetRef ref) {
  // sentenceListProvider를 read하여 전체 문장 목록을 가져옵니다.
  // read를 사용하는 이유는 이 함수 자체는 상태 변화를 감지할 필요가 없기 때문입니다.
  final List<String> sentences = ref.read(sentenceListProvider);
  if (sentences.isNotEmpty) {
    // Random 객체를 사용하여 목록 길이 범위 내에서 랜덤 인덱스 생성
    final randomIndex = Random().nextInt(sentences.length);
    // 해당 인덱스의 문장을 가져옴
    final newSentence = sentences[randomIndex];
    // currentGameSentenceProvider의 상태(state)를 새로 선택된 문장으로 업데이트
    // .notifier를 통해 StateController에 접근하여 state를 변경합니다.
    ref.read(currentGameSentenceProvider.notifier).state = newSentence;
    debugPrint("New sentence loaded: $newSentence"); // 디버깅용 로그
  } else {
    ref.read(currentGameSentenceProvider.notifier).state =
        "사용 가능한 문장이 없습니다."; // 예외 처리
    debugPrint("Error: No sentences available to load.");
  }
}
