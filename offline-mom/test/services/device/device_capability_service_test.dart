import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/ai_model_spec.dart';
import 'package:offline_mom/services/device/device_capability_service.dart';

void main() {
  group('recommendedTierForRamMb', () {
    test('returns anyModernPhone when RAM is unknown (null)', () {
      expect(recommendedTierForRamMb(null), RecommendedDeviceTier.anyModernPhone);
    });

    test('returns anyModernPhone for a low-RAM device (e.g. 4GB)', () {
      expect(recommendedTierForRamMb(3800), RecommendedDeviceTier.anyModernPhone);
    });

    test('returns anyModernPhone just below the high-RAM threshold', () {
      expect(recommendedTierForRamMb(5499), RecommendedDeviceTier.anyModernPhone);
    });

    test('returns highRamDevice at the threshold', () {
      expect(recommendedTierForRamMb(5500), RecommendedDeviceTier.highRamDevice);
    });

    test('returns highRamDevice for a nominal 8GB device', () {
      expect(recommendedTierForRamMb(7500), RecommendedDeviceTier.highRamDevice);
    });

    test('never returns highRamDevice for a zero or negative reading', () {
      expect(recommendedTierForRamMb(0), RecommendedDeviceTier.anyModernPhone);
      expect(recommendedTierForRamMb(-1), RecommendedDeviceTier.anyModernPhone);
    });
  });

  group('FakeDeviceCapabilityService', () {
    test('returns the configured RAM value', () async {
      final service = FakeDeviceCapabilityService(ramMb: 6000);
      expect(await service.totalRamMb(), 6000);
    });

    test('returns null when configured as unknown', () async {
      final service = FakeDeviceCapabilityService();
      expect(await service.totalRamMb(), isNull);
    });

    test('composes with recommendedTierForRamMb end-to-end', () async {
      final lowRam = FakeDeviceCapabilityService(ramMb: 3800);
      final highRam = FakeDeviceCapabilityService(ramMb: 8000);
      final unknown = FakeDeviceCapabilityService();

      expect(
        recommendedTierForRamMb(await lowRam.totalRamMb()),
        RecommendedDeviceTier.anyModernPhone,
      );
      expect(
        recommendedTierForRamMb(await highRam.totalRamMb()),
        RecommendedDeviceTier.highRamDevice,
      );
      expect(
        recommendedTierForRamMb(await unknown.totalRamMb()),
        RecommendedDeviceTier.anyModernPhone,
      );
    });
  });
}
