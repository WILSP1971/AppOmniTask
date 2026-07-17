import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../models/activity.dart';
import '../../calendar/data/activity_repository.dart';

part 'unscheduled_activities_provider.g.dart';

@riverpod
Future<List<Activity>> unscheduledActivities(UnscheduledActivitiesRef ref) {
  return ref.watch(activityRepositoryProvider).fetchUnscheduled();
}
