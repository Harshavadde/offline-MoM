import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/meeting.dart';
import '../../../../providers/app_providers.dart';

/// All meetings, most recent first. A plain [FutureProvider] is enough for
/// now (read-only in this phase); once recording/import can create meetings,
/// mutating actions will call `ref.invalidate(meetingListProvider)` to
/// refresh the list.
final meetingListProvider = FutureProvider<List<Meeting>>((ref) {
  return ref.watch(meetingRepositoryProvider).getAll();
});

/// `autoDispose` (Phase 4B) - a plain `.family` provider without it caches
/// one entry per unique id *forever*, for the life of the process, since
/// nothing ever evicts it once its last watcher goes away; over a long
/// session visiting many different meetings that's unbounded memory growth,
/// not a real leak in Dart's GC sense (nothing is unreachable) but a
/// slow-growing cache Riverpod's own `autoDispose` exists specifically to
/// prevent. Safe here: the only consumer is `MeetingDetailsScreen`, which
/// `ref.watch`es this for as long as it's on screen and no longer - the
/// same watched-while-visible lifetime `autoDispose` already assumes.
final meetingByIdProvider =
    FutureProvider.autoDispose.family<Meeting?, int>((ref, id) {
  return ref.watch(meetingRepositoryProvider).getById(id);
});
