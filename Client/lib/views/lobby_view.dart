import '../providers/lobby_providers.dart'; // providers 폴더의 파일 import
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'typing_view.dart'; // TypingView import

// TODO: Provider for participant count needed later
// final participantCountProvider = StateProvider<int>((ref) => 15); // Example

class LobbyView extends ConsumerWidget {
  const LobbyView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int currentParticipants = ref.watch(currentParticipantsProvider);
    final int maxParticipants = ref.watch(maxParticipantsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('라운드 로비'), // Lobby 화면 제목
        // 뒤로가기 버튼은 자동으로 생성됩니다 (HomeView에서 push 했으므로)
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0), // 전체적인 여백
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.spaceBetween, // 위젯들을 위/아래 공간으로 분산
          crossAxisAlignment: CrossAxisAlignment.stretch, // 자식 위젯들이 가로 폭 꽉 채우도록
          children: [
            // --- 상단: 참가자 정보 영역 ---
            Column(
              // 참가자 관련 정보를 묶기 위한 Column
              children: [
                const SizedBox(height: 40), // AppBar 아래 여백
                Row(
                  // 아이콘과 텍스트를 가로로 배치
                  mainAxisAlignment: MainAxisAlignment.center, // 가운데 정렬
                  children: [
                    const Icon(Icons.people_alt_outlined, size: 28), // 참가자 아이콘
                    const SizedBox(width: 8),
                    Text(
                      '참가자: $currentParticipants / $maxParticipants 명', // 임시 텍스트
                      style:
                          Theme.of(
                            context,
                          ).textTheme.headlineSmall, // 약간 큰 텍스트 스타일
                    ),
                  ],
                ),
                const SizedBox(height: 16), // 아래 텍스트와의 간격
                const Text(
                  '라운드 시작을 준비하세요!', // 임시 안내 텍스트
                  style: TextStyle(color: Colors.grey),
                ),
                // TODO: 라운드 시작까지 남은 시간 타이머 등 추가 가능
              ],
            ), // 참가자 정보 영역 끝
            // --- 중간: 광고 배너 슬롯 ---
            Container(
              // 자리 표시자 역할의 Container
              height: 60, // 배너 높이 예시 (나중에 실제 광고 크기에 맞춤)
              decoration: BoxDecoration(
                // 시각적 구분을 위한 스타일
                color: Colors.grey[300], // 회색 배경
                borderRadius: BorderRadius.circular(8), // 둥근 모서리
                border: Border.all(color: Colors.grey.shade400), // 얇은 테두리
              ),
              child: const Center(
                // 가운데 텍스트 표시
                child: Text(
                  '광고 배너 슬롯 (Ad Banner Slot)',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            ), // 광고 배너 슬롯 끝
            // --- 하단: 게임 시작 버튼 ---
            Center(
              // 버튼을 가로축 중앙에 배치
              child: ElevatedButton.icon(
                icon: const Icon(Icons.keyboard_alt_outlined), // 키보드 아이콘
                label: const Text('게임 시작'), // 버튼 텍스트
                style: ElevatedButton.styleFrom(
                  // 버튼 스타일
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 16,
                  ), // 내부 여백
                  textStyle: Theme.of(context).textTheme.titleMedium, // 텍스트 스타일
                ),
                onPressed: () {
                  // 버튼 클릭 시 동작
                  // TypingView 화면으로 이동
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const TypingView()),
                  );
                },
              ),
            ), // 게임 시작 버튼 끝
          ],
        ),
      ),
    );
  }
}
