import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class RoundAlarmScheduler {
  RoundAlarmScheduler._() {
    tz.initializeTimeZones();
  }
  static final _instance = RoundAlarmScheduler._();
  factory RoundAlarmScheduler() => _instance;

  final _fln = FlutterLocalNotificationsPlugin();

  /// 초기화: 권한 요청, 플러그인 초기화
  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _fln.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    // iOS 권한
    await _fln
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    // Android 13+ 권한
    await _fln
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  /// 앱 시작·리줌 시 한 번만 호출 → 오늘 남은 모든 알람 예약
  Future<void> refreshAlarms() async {
    // 1) 기존 알람 모두 취소
    await _fln.cancelAll();

    // 2) 미래 notifyAt 전체 문서 로드 (limit 없음)
    final now = Timestamp.now();
    final snap =
        await FirebaseFirestore.instance
            .collection('rounds')
            .where('notifyAt', isGreaterThan: now)
            .orderBy('notifyAt')
            .get();

    print('▶ refreshAlarms(): scheduling ${snap.docs.length} alarms');

    // 3) OS에 일괄 예약
    for (final doc in snap.docs) {
      final data = doc.data();
      final startTs = data['startAt'] as Timestamp;
      final notifyTs = data['notifyAt'] as Timestamp;

      // ① 실제 라운드 시작 시각 → 로컬 TZDateTime
      final startTz = tz.TZDateTime.from(startTs.toDate(), tz.local);
      // ② 알림 보낼 시각 → 로컬 TZDateTime
      final notifyTz = tz.TZDateTime.from(notifyTs.toDate(), tz.local);

      // 메시지는 startTz 기준으로 (예: “15:00 라운드에 참가하세요!”)
      final label = DateFormat.Hm().format(startTz);

      final id = doc.id.hashCode & 0x7fffffff;
      await _fln.zonedSchedule(
        id,
        '속타왕 라운드 알림',
        '$label 라운드에 참가하세요!',
        notifyTz,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'round_channel',
            'Round Alarms',
            importance: Importance.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }
}
