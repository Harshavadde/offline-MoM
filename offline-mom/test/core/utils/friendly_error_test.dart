import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/utils/friendly_error.dart';

void main() {
  group('friendlyErrorMessage', () {
    test('never returns raw exception text (no type names, no stack-trace-shaped strings)', () {
      final message = friendlyErrorMessage(Exception('Transcription failed: some internal detail'));
      expect(message.contains('Exception'), isFalse);
    });

    test('maps a network failure to a connectivity message', () {
      final message = friendlyErrorMessage(
        const FormatException('SocketException: Failed host lookup'),
      );
      expect(message, contains('internet connection'));
    });

    test('maps a timeout to a plain "took too long" message', () {
      final message = friendlyErrorMessage(Exception('LlmTimeoutException: generation stalled'));
      expect(message, contains('too long'));
    });

    test('maps a storage-full error to a plain storage message', () {
      final message = friendlyErrorMessage(Exception('OS Error: No space left on device, errno = 28'));
      expect(message, contains('storage space'));
    });

    test('maps a permission error to a plain permission message', () {
      final message = friendlyErrorMessage(Exception('Permission denied by the user'));
      expect(message, contains('Permission'));
    });

    test('maps a corrupted-file error to a plain corruption message', () {
      final message = friendlyErrorMessage(Exception('The model file appears corrupted'));
      expect(message, contains('corrupted'));
    });

    test('maps a missing-model error to a plain, actionable message', () {
      final message = friendlyErrorMessage(Exception('Model file not found on disk'));
      expect(message, contains('AI model'));
    });

    test('falls back to one honest generic message for anything unrecognized', () {
      final message = friendlyErrorMessage(Exception('some totally novel failure mode xyz123'));
      expect(message, 'Something went wrong. Please try again.');
    });

    test('never fabricates a specific cause for a generic error', () {
      final message = friendlyErrorMessage(Exception('xyz'));
      expect(message, isNot(contains('network')));
      expect(message, isNot(contains('storage')));
      expect(message, isNot(contains('permission')));
    });
  });
}
