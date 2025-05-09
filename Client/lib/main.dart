import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Riverpod 패키지
import 'package:firebase_core/firebase_core.dart'; // Firebase Core
import 'package:firebase_auth/firebase_auth.dart'; // Firebase Auth
import 'package:shared_preferences/shared_preferences.dart'; // SharedPreferences 추가
import 'views/home_view.dart'; // HomeView 화면
import 'services/notification_service.dart'; // NotificationService 추가

// main 함수를 비동기로 변경 (async 키워드 추가)
void main() async {
  // Flutter 엔진과 위젯 바인딩이 초기화되었는지 확인 (필수)
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase 앱 초기화
  await Firebase.initializeApp();

  // SharedPreferences 인스턴스 생성 (앱 시작 시 한 번만)
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  // NotificationService 초기화 및 SharedPreferences 인스턴스 주입을 위한 ProviderContainer 생성
  // 앱의 메인 ProviderScope보다 먼저 생성하여 초기화 로직에 사용합니다.
  final container = ProviderContainer(
    overrides: [
      // 이전에 NotificationService.dart 에서 정의한 sharedPreferencesProvider를
      // 위에서 생성한 실제 prefs 인스턴스로 값을 덮어씌웁니다.
      // 이렇게 하면 NotificationService 내에서 ref.watch(sharedPreferencesProvider)를 통해
      // 실제 SharedPreferences 인스턴스를 사용할 수 있게 됩니다.
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
  );

  // ProviderContainer를 통해 NotificationService 인스턴스를 얻고 초기화 함수 호출
  // .initialize()는 비동기 함수이므로 await 사용
  await container.read(notificationServiceProvider).initialize();
  print('main.dart: NotificationService 초기화 완료됨.');

  // 익명 로그인 시도 (기존 코드)
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

  // 앱 실행
  runApp(
    // ProviderScope를 사용하여 앱 전체에서 Riverpod Provider들을 사용할 수 있도록 합니다.
    // 이전 단계에서 생성한 container를 parent로 지정하여,
    // SharedPreferences 와 NotificationService가 초기화된 상태를 공유합니다.
    ProviderScope(
      parent: container, // 중요: 여기서 parent를 지정
      // 여기서는 더 이상 overrides를 할 필요가 없습니다. container 생성 시 이미 처리됨.
      child: const MyApp(),
    ),
  );
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
