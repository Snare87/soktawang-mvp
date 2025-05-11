import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 앱 전역에서 SharedPreferences 인스턴스를 주입·사용하기 위한 Provider.
/// main() 에서 overrideWithValue() 로 실제 prefs 인스턴스를 넣어 줍니다.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(),
);
