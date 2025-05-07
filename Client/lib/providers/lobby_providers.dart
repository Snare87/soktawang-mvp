import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 현재 참가자 수를 제공하는 Provider (임시 값)
final currentParticipantsProvider = Provider<int>((ref) {
  // TODO: 나중에 실제 라운드 데이터와 연결 필요 (예: RTDB 리스너)
  return 15;
});

/// 최대 참가자 수를 제공하는 Provider (임시 값)
final maxParticipantsProvider = Provider<int>((ref) {
  // TODO: 라운드 설정 등에서 읽어오기
  return 50;
});
