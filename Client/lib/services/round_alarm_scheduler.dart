import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// 알람 3개를 `notifyAt` 필드 기준으로 예약·재갱신
class RoundAlarmScheduler {
  RoundAlarmScheduler._() {
    tz.initializeTimeZones();
  }
  static final RoundAlarmScheduler _instance = RoundAlarmScheduler._();
  factory RoundAlarmScheduler() => _instance;

  final _fln = FlutterLocalNotificationsPlugin();

  /// 앱 시작·포그라운드 복귀 시 호출
  Future<void> refreshAlarms() async {
    await _fln.cancelAll();

    final now = Timestamp.now();
    final q =
        await FirebaseFirestore.instance
            .collection('rounds')
            .where('notifyAt', isGreaterThan: now)
            .orderBy('notifyAt')
            .limit(3)
            .get();

    for (final doc in q.docs) {
      final data = doc.data();
      final notifyAt = (data['notifyAt'] as Timestamp).toDate();
      final roundId = doc.id;
      final alarmId = roundId.hashCode & 0x7fffffff;

      await _fln.zonedSchedule(
        alarmId,
        '속타왕 라운드 알림',
        '${DateFormat.Hm().format(notifyAt)} 라운드에 참가하세요!',
        tz.TZDateTime.from(notifyAt, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'round_channel',
            'Round Alarms',
            importance: Importance.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }
}
