import 'dart:io';

/// A best-effort "is there any internet connection at all right now"
/// check (V2.2 Production Hardening, Priority 4 - real-device QA finding:
/// the Recommended Setup flow gave no explanation when it failed on a
/// device with no connection, just a raw download error after the fact).
///
/// Deliberately not a new dependency (`connectivity_plus` or similar) -
/// `dart:io`'s own `InternetAddress.lookup` is already available in every
/// Dart/Flutter app and is sufficient for this app's one use of it (a
/// pre-flight check before a model download, not a live connectivity
/// stream). A short, bounded timeout so a slow/unreachable DNS server
/// fails fast rather than stalling the check itself. Never throws - a
/// lookup failure of any kind (no connection, DNS blocked, timeout) is
/// treated as "no connection", the only actionable answer this function
/// needs to give.
Future<bool> hasInternetConnection() async {
  try {
    final result = await InternetAddress.lookup('huggingface.co')
        .timeout(const Duration(seconds: 5));
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } on Object {
    return false;
  }
}
