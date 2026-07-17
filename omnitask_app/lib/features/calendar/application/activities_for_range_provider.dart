import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../models/activity.dart';
import '../data/activity_repository.dart';
import 'visible_range_provider.dart';

part 'activities_for_range_provider.g.dart';

@riverpod
Future<List<Activity>> activitiesForRange(ActivitiesForRangeRef ref) async {
  final range = ref.watch(visibleRangeProvider);
  final repo = ref.watch(activityRepositoryProvider);
  final paged = await repo.fetchActivities(from: range.start, to: range.end);
  return paged.items;
}

@riverpod
Future<Activity> activityDetail(ActivityDetailRef ref, String activityId) {
  return ref.watch(activityRepositoryProvider).fetchById(activityId);
}
