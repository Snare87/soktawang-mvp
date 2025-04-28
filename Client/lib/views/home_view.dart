import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ↓↓↓ 클래스 이름은 파일명에 맞게 변경 (예: LobbyView, TypingView)
class HomeView extends ConsumerWidget {
  // ↓↓↓ 여기도 클래스 이름과 동일하게 변경
  const HomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Scaffold는 기본적인 화면 레이아웃 구조를 제공합니다.
    return Scaffold(
      appBar: AppBar(
         // ↓↓↓ AppBar 제목도 화면에 맞게 변경
        title: const Text('Home View'),
      ),
      body: const Center(
         // ↓↓↓ Body 내용도 화면에 맞게 변경 (일단은 텍스트만)
        child: Text('Home View Content Placeholder'),
      ),
    );
  }
}