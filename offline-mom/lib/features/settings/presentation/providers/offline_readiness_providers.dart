import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../providers/app_providers.dart';
import '../../../../services/offline/offline_readiness_service.dart';

/// The Offline Readiness screen's report (reliability-overhaul pass, Phase
/// 15/16) - `autoDispose` since the report can go stale the moment the
/// user leaves this screen and downloads/activates a different model
/// elsewhere; re-evaluated fresh every time the screen is opened rather
/// than cached across the whole app session.
final offlineReadinessReportProvider = FutureProvider.autoDispose<OfflineReadinessReport>((ref) {
  const service = OfflineReadinessService();
  return service.evaluate(ref.watch(installedModelRepositoryProvider));
});
