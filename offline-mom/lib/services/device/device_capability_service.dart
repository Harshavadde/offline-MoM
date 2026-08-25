import 'package:device_info_plus/device_info_plus.dart';

import '../../models/ai_model_spec.dart';

/// Reads this device's total physical RAM, so the app can *recommend* (never
/// require) a stronger optional AI model for Resume tailoring
/// (docs/v3/01-prd.md §13). The only consumer of a raw RAM figure is
/// [recommendedTierForRamMb] below - nothing else in this app should read
/// [totalRamMb] directly and branch on a raw number, the same "coarse
/// bucket, not a false-precision figure" discipline [RecommendedDeviceTier]
/// itself already applies.
abstract class DeviceCapabilityService {
  /// Total physical RAM in megabytes, or `null` if it could not be
  /// determined (older Android versions, a plugin failure, a platform this
  /// figure isn't available on). Callers must treat `null` the same as
  /// "unknown" - never as zero, and never as a reason to block the Resume
  /// feature (docs/v3/01-prd.md §18: a RAM-read failure falls back to the
  /// lowest tier, it never crashes or blocks).
  Future<int?> totalRamMb();
}

/// Maps a (possibly unknown) RAM reading to the coarse device-capability
/// bucket [ModelCatalog] entries are already labeled with
/// ([RecommendedDeviceTier], `lib/models/ai_model_spec.dart`) - a pure
/// function, deliberately free of any plugin dependency, so the threshold
/// itself is unit-testable without a device or a fake plugin.
///
/// Threshold note (disclosed, not asserted as precise): Android's own
/// `ActivityManager.MemoryInfo.totalMem` - what [DeviceCapabilityService
/// .totalRamMb] ultimately reads - typically reports somewhat below a
/// phone's nominal marketing RAM figure (OS/firmware-reserved memory), so a
/// nominal "6GB" device often reports closer to 5.5-5.8GB. 5500MB is chosen
/// as the `highRamDevice` cutoff specifically to give that headroom rather
/// than requiring the full nominal 6144MB - this has not been calibrated
/// against a real device in this implementation environment (same standing
/// limitation as every other AI-memory figure in this codebase, e.g.
/// [AiModelSpec.ramRequirementMb]'s own doc comment) and may need
/// adjustment once real-device readings are available.
RecommendedDeviceTier recommendedTierForRamMb(int? ramMb) {
  if (ramMb != null && ramMb >= 5500) {
    return RecommendedDeviceTier.highRamDevice;
  }
  return RecommendedDeviceTier.anyModernPhone;
}

class DeviceInfoDeviceCapabilityService implements DeviceCapabilityService {
  DeviceInfoDeviceCapabilityService({DeviceInfoPlugin? deviceInfoPlugin})
      : _deviceInfoPlugin = deviceInfoPlugin ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _deviceInfoPlugin;

  @override
  Future<int?> totalRamMb() async {
    try {
      final info = await _deviceInfoPlugin.androidInfo;
      return info.physicalRamSize;
    } catch (_) {
      // Any plugin failure (non-Android platform, an OS version that
      // doesn't expose this, a genuine platform-channel error) degrades to
      // "unknown," never a crash - see this class's own doc comment.
      return null;
    }
  }
}

/// Test double for [DeviceCapabilityService] - no plugin, no platform
/// channel, mirrors [FakeModelDownloadService]'s role as the one seam in
/// its feature genuinely untestable under `flutter test` (real device
/// hardware here, real sockets there).
class FakeDeviceCapabilityService implements DeviceCapabilityService {
  FakeDeviceCapabilityService({this.ramMb});

  /// The value [totalRamMb] returns - `null` simulates an undetermined
  /// reading.
  final int? ramMb;

  @override
  Future<int?> totalRamMb() async => ramMb;
}
