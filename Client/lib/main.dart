import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/round_alarm_scheduler_provider.dart';
import 'services/round_alarm_scheduler.dart';
import 'providers/shared_preferences_provider.dart';
import 'views/home_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // 실제 SharedPreferences 인스턴스 생성
  final prefs = await SharedPreferences.getInstance();

  // 알람 스케줄러 초기화
  final scheduler = RoundAlarmScheduler();
  await scheduler.init();
  await scheduler.refreshAlarms();

  // ProviderScope 에 sharedPreferencesProvider override
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});
  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ③ 포그라운드 복귀 시에도 한 번만 재등록
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(roundAlarmSchedulerProvider).refreshAlarms();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '속타왕 MVP',
      theme: ThemeData(useMaterial3: true),
      home: const HomeView(),
    );
  }
}
