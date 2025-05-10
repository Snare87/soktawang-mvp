import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/round_alarm_scheduler.dart';

final roundAlarmSchedulerProvider = Provider<RoundAlarmScheduler>(
  (_) => RoundAlarmScheduler(),
);
