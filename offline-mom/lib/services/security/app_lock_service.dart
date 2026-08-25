/// Contract for gating access to the app with whatever secure lock the
/// device itself already has configured (PIN/pattern/password/biometric) -
/// deliberately not an app-specific account or password, since the app has
/// no accounts of any kind.
abstract class AppLockService {
  /// Whether the device has a secure lock (biometric or PIN/pattern/
  /// password) configured at all. If false, enabling app lock would lock
  /// the user out with no way to unlock, so callers must check this first.
  Future<bool> isSupported();

  /// Prompts the device's own authentication UI. Returns true only on
  /// successful authentication.
  Future<bool> authenticate(String reason);
}
