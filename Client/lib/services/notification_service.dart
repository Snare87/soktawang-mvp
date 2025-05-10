// lib/services/notification_service.dart

import 'package:flutter/foundation.dart'; // debugPrint 사용 위함
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Riverpod 사용
import 'package:shared_preferences/shared_preferences.dart'; // SharedPreferences 사용
import 'package:timezone/data/latest_all.dart' as tz; // timezone 초기화
import 'package:timezone/timezone.dart' as tz; // timezone 사용

// --- Riverpod Providers ---

// NotificationService 인스턴스를 제공하는 Provider
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(ref); // Ref를 NotificationService에 전달
});

// 알람 설정(ON/OFF) 상태를 관리하는 StateNotifierProvider
const String alarmEnabledKey = 'soktawang_alarm_enabled'; // SharedPreferences 키

final alarmSettingsProvider =
    StateNotifierProvider<AlarmSettingsNotifier, bool>((ref) {
      // SharedPreferencesProvider를 watch하여 SharedPreferences 인스턴스를 가져옴
      // 앱 시작 시 main.dart에서 SharedPreferences 인스턴스를 override 해줘야 함
      final prefs = ref.watch(sharedPreferencesProvider);
      return AlarmSettingsNotifier(prefs);
    });

class AlarmSettingsNotifier extends StateNotifier<bool> {
  AlarmSettingsNotifier(this._prefs)
    // SharedPreferences에서 저장된 값 불러오기, 없으면 true (기본 ON)
    : super(_prefs.getBool(alarmEnabledKey) ?? true);

  final SharedPreferences _prefs;

  Future<void> setAlarmEnabled(bool isEnabled) async {
    await _prefs.setBool(alarmEnabledKey, isEnabled);
    state = isEnabled; // 상태 업데이트하여 UI에 반영
    debugPrint('알람 설정 변경: $state');
  }
}

// SharedPreferences 인스턴스를 제공하는 Provider (main.dart에서 override 필수)
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  // 이 Provider는 main.dart에서 실제 SharedPreferences 인스턴스로 override되어야 합니다.
  // ProviderScope(overrides: [sharedPreferencesProvider.overrideWithValue(prefsInstance)]) 형태로.
  throw UnimplementedError(
    'SharedPreferences provider must be overridden in main.dart',
  );
});

// --- NotificationService 클래스 ---

class NotificationService {
  final Ref _ref; // Riverpod Ref를 사용하기 위해 멤버 변수 추가
  NotificationService(this._ref); // 생성자에서 Ref 인스턴스 받기

  // FlutterLocalNotificationsPlugin 인스턴스 생성
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // 알림 서비스 초기화 함수
  Future<void> initialize() async {
    tz.initializeTimeZones(); // Timezone 데이터 초기화

    // 애플리케이션의 기본 로컬 시간대를 설정합니다.
    // 한국에서 서비스한다면 'Asia/Seoul'로 고정하는 것이 좋습니다.
    // 또는 flutter_native_timezone 패키지를 사용하여 기기의 실제 시간대를 가져올 수도 있습니다.
    try {
      // final String currentTimeZone = await FlutterNativeTimezone.getLocalTimezone();
      // tz.setLocalLocation(tz.getLocation(currentTimeZone));
      tz.setLocalLocation(tz.getLocation('Asia/Seoul')); // <--- 이 부분을 활성화!
      debugPrint('[NotificationService] 로컬 타임존 설정: Asia/Seoul');
    } catch (e) {
      debugPrint('[NotificationService] 타임존 설정 중 오류: $e');
      // 기본 UTC로 동작하거나, 에러 처리를 할 수 있습니다.
    }
    // Android 초기화 설정
    // '@mipmap/ic_launcher'는 기본 앱 아이콘을 사용하겠다는 의미입니다.
    // 'app_icon' 등으로 변경하여 'android/app/src/main/res/drawable' 폴더에 해당 이름의 아이콘 파일이 있다면 그것을 사용할 수 있습니다.
    const AndroidInitializationSettings androidInitializationSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS 초기화 설정
    const DarwinInitializationSettings
    iosInitializationSettings = DarwinInitializationSettings(
      requestAlertPermission: true, // 알림 권한 요청
      requestBadgePermission: true, // 뱃지 권한 요청
      requestSoundPermission: true, // 소리 권한 요청
      // onDidReceiveLocalNotification: onDidReceiveLocalNotification, // 오래된 iOS 버전(<10)에서 포그라운드 알림 처리 콜백
    );

    // 통합 초기화 설정
    final InitializationSettings initializationSettings =
        InitializationSettings(
          android: androidInitializationSettings,
          iOS: iosInitializationSettings,
        );

    // 플러그인 초기화
    // onDidReceiveNotificationResponse: 알림을 탭했을 때 호출되는 콜백 (앱이 실행 중일 때)
    // onDidReceiveBackgroundNotificationResponse: 알림을 탭했을 때 호출되는 콜백 (앱이 백그라운드/종료 상태일 때)
    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          _onDidReceiveBackgroundNotificationResponse,
    );

    debugPrint('NotificationService 초기화 완료');

    // iOS 및 Android 특정 권한 요청 (앱 시작 시 권한을 명시적으로 받는 것이 좋음)
    await requestPermissions();
  }

  // 필요한 권한을 요청하는 함수
  Future<void> requestPermissions() async {
    // Android 13 (API 33) 이상을 위한 알림 권한 요청
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    // 일반 알림 권한
    await androidImplementation?.requestNotificationsPermission();
    // 정확한 시간 알람 권한 (선택적이지만, 게임 라운드 알림에는 유용)
    await androidImplementation?.requestExactAlarmsPermission();

    // iOS 알림 권한 요청 (initialize에서 이미 true로 설정했지만, 여기서도 명시적으로 호출 가능)
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    debugPrint('알림 권한 요청 시도 완료');
  }

  // 알림 클릭 시 실행될 콜백 (앱이 포그라운드 또는 백그라운드에 있을 때)
  // 이 콜백은 main isolate에서 실행됩니다.
  void _onDidReceiveNotificationResponse(NotificationResponse response) {
    debugPrint(
      '알림 탭 응답 수신: 페이로드 - ${response.payload}, ID - ${response.id}, 액션ID - ${response.actionId}',
    );
    if (response.payload != null && response.payload!.isNotEmpty) {
      // TODO: 페이로드(payload)를 사용하여 앱 내 특정 화면으로 이동하거나 데이터 처리
      // 예시: 메인 화면으로 이동 후 특정 탭을 연다거나, 특정 라운드 정보를 보여준다거나 등.
      // 이 부분은 앱의 네비게이션 구조에 따라 달라집니다 (GoRouter, Navigator 2.0 등).
      // 지금은 단순히 로그만 출력합니다.
      debugPrint("페이로드 내용: ${response.payload}");
    }
  }

  // 알림 클릭 시 실행될 콜백 (앱이 종료된 상태에서 알림을 탭하여 실행될 때)
  // 이 콜백은 새로운 isolate에서 실행될 수 있으므로, Flutter 엔진 바인딩 등이 필요할 수 있습니다.
  // UI 업데이트나 Riverpod Provider 직접 접근 등은 여기서 바로 하기 어렵습니다.
  // 보통 SharedPreferences에 값을 쓰거나, 앱 실행 시 이 payload를 확인하여 처리합니다.
  @pragma('vm:entry-point') // Dart AOT 컴파일러에게 이 함수를 유지하도록 지시
  static void _onDidReceiveBackgroundNotificationResponse(
    NotificationResponse response,
  ) {
    // 백그라운드에서 수신 시 어떤 작업을 할지 정의합니다.
    // 예: SharedPreferences에 클릭된 알림 정보 저장 후, 앱 실행 시 해당 정보 확인.
    // 이 예제에서는 로그만 남깁니다. 실제 앱에서는 추가 작업이 필요할 수 있습니다.
    debugPrint('백그라운드 알림 탭 응답 수신: 페이로드 - ${response.payload}');
    // WidgetsFlutterBinding.ensureInitialized(); // 만약 여기서 Flutter 관련 작업이 필요하다면
  }

  // 특정 시간에 알림을 예약하는 함수
  Future<void> scheduleNotification({
    required int id, // 각 알림을 구분하는 고유 ID
    required String title, // 알림 제목
    required String body, // 알림 내용
    required DateTime scheduledTime, // 알림이 표시될 시간
    String? payload, // 알림 클릭 시 전달될 데이터 (선택 사항)
  }) async {
    // 사용자의 알람 설정 값 가져오기 (Riverpod 사용)
    final bool alarmsEnabled = _ref.read(alarmSettingsProvider);
    if (!alarmsEnabled) {
      debugPrint('알람 설정이 꺼져있어 ID $id 알림을 스케줄링하지 않습니다.');
      return; // 알람 설정이 꺼져있으면 아무것도 안 함
    }

    // 예약하려는 시간이 이미 과거인지 확인 (약간의 오차 허용)
    if (scheduledTime.isBefore(
      DateTime.now().add(const Duration(seconds: 10)),
    )) {
      debugPrint(
        'ID $id 알림의 스케줄링 시간 ($scheduledTime)이 이미 지났거나 너무 임박하여 스케줄링하지 않습니다.',
      );
      return;
    }

    // 동일 ID로 이미 예약된 알림이 있다면, 먼저 취소하여 중복 방지
    await _notificationsPlugin.cancel(id);
    debugPrint('ID $id 기존 알림 취소 시도 (중복 방지)');

    try {
      // 알림 예약 실행
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(
          scheduledTime,
          tz.local,
        ), // tz.local은 위에서 setLocalLocation으로 설정된 시간대를 따름
        NotificationDetails(
          // Android 알림 상세 설정
          android: AndroidNotificationDetails(
            'soktawang_round_alarm_channel_id', // 채널 ID (앱마다 고유하게)
            '라운드 시작 알림', // 채널 이름 (사용자에게 표시됨)
            channelDescription: '속타왕 게임 라운드 시작을 알려주는 알림입니다.', // 채널 설명
            importance: Importance.max, // 중요도 (최상)
            priority: Priority.high, // 우선순위 (높음)
            playSound: true, // 소리 재생 여부
            // sound: RawResourceAndroidNotificationSound('custom_sound'), // res/raw/custom_sound.mp3 같은 커스텀 사운드
            icon: '@mipmap/ic_launcher', // 알림 아이콘 (선택 사항, 없으면 기본 앱 아이콘)
            // largeIcon: DrawableResourceAndroidBitmap('large_icon_name'), // 큰 아이콘 (선택 사항)
          ),
          // iOS 알림 상세 설정
          iOS: const DarwinNotificationDetails(
            presentAlert: true, // 알림 표시 여부
            presentBadge: true, // 앱 아이콘에 뱃지 표시 여부
            presentSound: true, // 소리 재생 여부
            // sound: 'custom_sound.aiff', // 커스텀 사운드 (프로젝트에 추가 필요)
          ),
        ),
        payload: payload, // 알림 클릭 시 전달할 데이터
        androidScheduleMode:
            AndroidScheduleMode
                .exactAllowWhileIdle, // Android Doze 모드에서도 정확한 시간에 알림
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime, // 절대 시간 기준으로 해석
      );
      debugPrint('ID $id 알림 예약 완료: $scheduledTime - "$title"');
    } catch (e) {
      debugPrint('ID $id 알림 예약 중 오류 발생: $e');
    }
  }

  // 특정 ID의 알림을 취소하는 함수
  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
    debugPrint('ID $id 알림 취소 완료.');
  }

  // 예약된 모든 알림을 취소하는 함수
  Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
    debugPrint('예약된 모든 알림 취소 완료.');
  }
}
