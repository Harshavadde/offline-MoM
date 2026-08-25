/// Maps a raw exception to plain, user-appropriate language (V2.2
/// Production Hardening, Priority 6 - real-device QA finding: several
/// screens showed `Object.toString()` of a caught exception directly to
/// the user, e.g. "Transcription failed: TimeoutException: ..." or a bare
/// `SocketException` message).
///
/// Deliberately pattern-matches on the *type name* embedded in
/// [Object.toString] rather than requiring every call site to `catch`
/// specific exception types - most callers of this function are UI code
/// several layers away from where the exception was actually thrown
/// (e.g. a stored `Meeting.errorMessage`/`Document.errorMessage` string,
/// already flattened to text by the use case that caught it - see
/// `TranscribeMeetingUseCase`'s `'Transcription failed: $e'` convention),
/// so there is no live exception object left to type-check against by the
/// time this runs. This is display-only: it never changes what's stored
/// in the database or logged via `AppLogger` - the technical detail stays
/// available internally, only what's *shown* changes.
///
/// Deliberately conservative: only maps patterns confidently identifiable
/// from common Dart/Flutter/plugin exception text (network, storage,
/// permission, file/model corruption/missing). Anything unrecognized
/// falls through to one honest, generic message rather than a guessed
/// specific one - never fabricates a cause this function can't actually
/// tell happened.
String friendlyErrorMessage(Object error) {
  final raw = error.toString();
  final lower = raw.toLowerCase();

  bool has(String s) => lower.contains(s);

  if (has('socketexception') ||
      has('failed host lookup') ||
      has('network is unreachable') ||
      has('connection refused') ||
      has('connection reset') ||
      has('no address associated with hostname')) {
    return 'No internet connection. Check your connection and try again.';
  }
  if (has('timeoutexception') || has('timed out') || has('stalled')) {
    return 'This took too long and was stopped. Check your connection or '
        'try again.';
  }
  if (has('no space left on device') || has('errno = 28') || has('enospc')) {
    return 'Not enough storage space on this device. Free up some space '
        'and try again.';
  }
  if (has('permission') && (has('denied') || has('permissionstatus'))) {
    return 'Permission was denied. Grant the required permission in your '
        'device settings and try again.';
  }
  if (has('corrupt') || has('checksum') || has('sha256') || has('appears corrupted')) {
    return 'This file appears to be corrupted or incomplete. Try '
        'downloading or importing it again.';
  }
  if (has('model') && (has('not found') || has('missing') || has('no such file'))) {
    return 'The AI model could not be found. It may need to be '
        'downloaded again from Settings > AI Models.';
  }
  if (has('filesystemexception') || has('no such file or directory')) {
    return 'A required file could not be found on this device.';
  }
  if (has('outofmemoryerror') || has('out of memory')) {
    return 'This device ran out of memory while processing. Try closing '
        'other apps and try again.';
  }

  return 'Something went wrong. Please try again.';
}
