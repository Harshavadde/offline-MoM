import 'package:local_auth/local_auth.dart';

import 'app_lock_service.dart';

/// [AppLockService] backed by `local_auth`: the device's own biometric
/// prompt, falling back to PIN/pattern/password (`biometricOnly: false`)
/// when biometrics aren't enrolled - exactly the "device lock", not an
/// app-specific credential.
class LocalAuthAppLockService implements AppLockService {
  final _localAuth = LocalAuthentication();

  @override
  Future<bool> isSupported() => _localAuth.isDeviceSupported();

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
      );
    } on Exception {
      return false;
    }
  }
}
