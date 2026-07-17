import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../backlog/application/unscheduled_activities_provider.dart';
import '../data/activity_repository.dart';
import 'activities_for_range_provider.dart';

part 'activity_actions_controller.g.dart';

/// Completar y cancelar pasan por el mismo PATCH del backend (§6, §14) —
/// cancelar cancela los reminders pendientes sin enviarlos.
@riverpod
class ActivityActionsController extends _$ActivityActionsController {
  @override
  FutureOr<void> build(String activityId) {}

  Future<void> markCompleted() => _run(() => ref
      .read(activityRepositoryProvider)
      .update(activityId, status: 'completed'));

  Future<void> cancel() =>
      _run(() => ref.read(activityRepositoryProvider).cancel(activityId));

  Future<void> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await action();
      ref.invalidate(activityDetailProvider(activityId));
      ref.invalidate(activitiesForRangeProvider);
      ref.invalidate(unscheduledActivitiesProvider);
    });
  }
}
