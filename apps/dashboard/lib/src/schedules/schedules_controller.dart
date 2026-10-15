import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/schedules.dart';
import '../auth/auth_controller.dart';

/// A quem pertencem os agendamentos: uma TV ou um grupo.
typedef ScheduleTarget = ({String? deviceId, int? groupId});

/// Agendamentos de [ScheduleTarget], na ordem de precedência.
final schedulesProvider = FutureProvider.autoDispose
    .family<List<Schedule>, ScheduleTarget>((ref, target) async {
  final list = await ref.watch(apiClientProvider).listSchedules(
        deviceId: target.deviceId,
        groupId: target.groupId,
      );
  return [...list]..sort(compareByPrecedence);
});
