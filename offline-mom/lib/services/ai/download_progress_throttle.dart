/// Caps how often a download's progress callback actually fires.
///
/// A large file's download can report progress thousands of times (once
/// per network chunk, which can be just a few KB) - calling straight
/// through to a Riverpod state update and widget rebuild that often, on
/// every single chunk, floods the UI thread badly enough to look like the
/// app has hung, especially with two downloads running in parallel (see
/// `OnboardingSetupController`). This lets at most one callback through per
/// [minInterval]; callers should still emit the final 100% unconditionally
/// once a download actually finishes, so the UI never looks stuck short of
/// done.
class ProgressThrottle {
  ProgressThrottle({this.minInterval = const Duration(milliseconds: 150)});

  final Duration minInterval;
  DateTime? _last;

  bool shouldEmit() {
    final now = DateTime.now();
    final last = _last;
    if (last != null && now.difference(last) < minInterval) return false;
    _last = now;
    return true;
  }
}
