import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Riverpod 패키지 import
import 'package:firebase_core/firebase_core.dart'; // Firebase Core 패키지 import
import 'package:firebase_auth/firebase_auth.dart'; // Firebase Auth 패키지 import
import 'views/home_view.dart'; // 시작 화면 import

void main() async {
  // 비동기 main
  // runApp 전에 Flutter 바인딩 초기화
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase 앱 초기화
  await Firebase.initializeApp();

  // 익명 로그인 시도 (앱 시작 시)
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      final userCredential = await FirebaseAuth.instance.signInAnonymously();
      print("Signed in anonymously with uid: ${userCredential.user?.uid}");
    } else {
      print("Already signed in with uid: ${user.uid}");
    }
  } catch (e) {
    print("Error signing in anonymously: $e");
  }

  // Riverpod ProviderScope로 앱 감싸서 실행
  runApp(const ProviderScope(child: MyApp()));
}

// 앱 최상위 위젯
class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: '속타왕 MVP', // 앱 제목
      theme: ThemeData(
        // 앱 테마
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeView(), // 시작 화면 지정
      debugShowCheckedModeBanner: false, // 디버그 배너 숨기기 (선택 사항)
    );
  }
}
