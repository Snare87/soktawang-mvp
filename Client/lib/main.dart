import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';// Riverpod 패키지 import
import 'views/home_view.dart'; 

void main() {
  // 앱 전체를 ProviderScope로 감싸서 Riverpod 상태 관리를 활성화합니다.
  runApp(const ProviderScope(child: MyApp()));
}

// 앱의 최상위 위젯. ConsumerWidget으로 만들어 Riverpod 상태를 읽을 수 있게 합니다.
class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) { // WidgetRef ref 파라미터 추가
    // MaterialApp이 앱의 기본적인 디자인과 네비게이션을 제공합니다.
    return MaterialApp(
      title: '속타왕 MVP', // 앱의 제목
      theme: ThemeData( // 앱의 전반적인 테마 (나중에 더 상세히 설정)
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeView(),
    );
  }
}