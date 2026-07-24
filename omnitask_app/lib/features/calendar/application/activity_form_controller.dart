import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../models/activity.dart';
import '../../../models/activity_draft.dart';
import '../../backlog/application/unscheduled_activities_provider.dart';
import '../data/activity_repository.dart';
import 'activities_for_range_provider.dart';

part 'activity_form_controller.g.dart';

/// Invalidar el calendario y el backlog juntos, siempre, es intencional: una
/// edición puede mover una actividad de una lista a la otra (asignarle fecha
/// la saca del backlog; quitarla la mete) y no vale la pena decidir cuál
/// invalidar cuando invalidar ambas es barato (§14).
@riverpod
class ActivityFormController extends _$ActivityFormController {
  @override
  FutureOr<void> build() {}

  Future<Activity?> create(ActivityDraft draft) =>
      _submit(() => ref.read(activityRepositoryProvider).create(draft));

  // Nombrado updateActivity, no update: AsyncNotifierBase ya define un método
  // update(cb) propio de Riverpod — reusar ese nombre choca con esa firma.
  Future<Activity?> updateActivity(
    String id, {
    String? title,
    String? description,
    DateTime? startsAt,
    bool clearStartsAt = false,
    DateTime? endsAt,
    bool clearEndsAt = false,
    String? location,
    String? meetingUrl,
    String? meetingProvider,
    List<String>? contactIds,
  }) =>
      _submit(() => ref.read(activityRepositoryProvider).update(
            id,
            title: title,
            description: description,
            startsAt: startsAt,
            clearStartsAt: clearStartsAt,
            endsAt: endsAt,
            clearEndsAt: clearEndsAt,
            location: location,
            meetingUrl: meetingUrl,
            meetingProvider: meetingProvider,
            contactIds: contactIds,
          ));

  Future<Activity?> _submit(Future<Activity> Function() action) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(action);
    state = result;
    if (result.hasValue) {
      ref.invalidate(activitiesForRangeProvider);
      ref.invalidate(unscheduledActivitiesProvider);
    }
    return result.valueOrNull;
  }
}
