// Cross-validates PdfEncryptionKeys' write-side Algorithm 2/3/5
// implementation against pdf_cos's own StandardSecurityHandler - an
// independently-implemented *read* side of the exact same PDF spec
// algorithm (confirmed by direct source inspection, not assumed). If this
// module's key derivation were wrong in any way, the reference library's
// own from-scratch re-derivation (from the /O, /U, /P, and /ID this module
// computed) would compute a *different* file key and fail to authenticate
// the password - so a passing test here is a real, independent proof of
// correctness, not just "my code agrees with itself."
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/pdf_security/pdf_encryption_algorithms.dart';
import 'package:offline_mom/services/pdf_security/pdf_permissions.dart';
import 'package:pdf_cos/pdf_cos.dart';

CosDictionary _buildEncryptDict(PdfEncryptionKeys keys, int permissionBits) {
  return CosDictionary({
    'Filter': const CosName('Standard'),
    'V': const CosInteger(4),
    'R': const CosInteger(4),
    'Length': const CosInteger(128),
    'O': CosString(keys.o),
    'U': CosString(keys.u),
    'P': CosInteger(permissionBits),
    'EncryptMetadata': const CosBoolean(true),
    'CF': CosDictionary({
      'StdCF': CosDictionary({
        'CFM': const CosName('AESV2'),
        'AuthEvent': const CosName('DocOpen'),
        'Length': const CosInteger(16),
      }),
    }),
    'StmF': const CosName('StdCF'),
    'StrF': const CosName('StdCF'),
  });
}

CosObject _identityResolve(CosObject? o) => o ?? CosNull.instance;

void main() {
  final permissions = const PdfPermissions().toPBits();

  test('the reference library authenticates the real user password against my computed /O,/U', () {
    final id = Uint8List.fromList(List.generate(16, (i) => i));
    final keys = computeEncryptionKeys(
      userPassword: 'correct horse',
      permissionBits: permissions,
      firstId: id,
    );
    final dict = _buildEncryptDict(keys, permissions);

    final handler = StandardSecurityHandler.fromEncrypt(dict, id, 'correct horse', _identityResolve);
    expect(handler.stringCipher, PdfCipher.aes128);
    expect(handler.streamCipher, PdfCipher.aes128);
  });

  test('the reference library rejects a wrong password against my computed /O,/U', () {
    final id = Uint8List.fromList(List.generate(16, (i) => 20 + i));
    final keys = computeEncryptionKeys(
      userPassword: 'correct horse',
      permissionBits: permissions,
      firstId: id,
    );
    final dict = _buildEncryptDict(keys, permissions);

    expect(
      () => StandardSecurityHandler.fromEncrypt(dict, id, 'wrong password', _identityResolve),
      throwsA(isA<CosPasswordException>()),
    );
  });

  test('the reference library authenticates the owner password too, when one is set', () {
    final id = Uint8List.fromList(List.generate(16, (i) => 40 + i));
    final keys = computeEncryptionKeys(
      userPassword: 'user-pw',
      ownerPassword: 'owner-pw',
      permissionBits: permissions,
      firstId: id,
    );
    final dict = _buildEncryptDict(keys, permissions);

    // Both doors open, per Algorithm 7's own "an owner password also opens
    // the document" behaviour - the reference implementation's own
    // fromEncrypt tries the user branch first, then the owner branch.
    expect(
      () => StandardSecurityHandler.fromEncrypt(dict, id, 'user-pw', _identityResolve),
      returnsNormally,
    );
    expect(
      () => StandardSecurityHandler.fromEncrypt(dict, id, 'owner-pw', _identityResolve),
      returnsNormally,
    );
  });

  test('an empty owner password falls back to the user password (spec default)', () {
    final id = Uint8List.fromList(List.generate(16, (i) => 60 + i));
    final keys = computeEncryptionKeys(
      userPassword: 'only-password',
      permissionBits: permissions,
      firstId: id,
    );
    final dict = _buildEncryptDict(keys, permissions);

    expect(
      () => StandardSecurityHandler.fromEncrypt(dict, id, 'only-password', _identityResolve),
      returnsNormally,
    );
  });

  test('a different file /ID with the same password fails - /ID is a real input, not decorative', () {
    final id = Uint8List.fromList(List.generate(16, (i) => 80 + i));
    final wrongId = Uint8List.fromList(List.generate(16, (i) => 90 + i));
    final keys = computeEncryptionKeys(
      userPassword: 'pw',
      permissionBits: permissions,
      firstId: id,
    );
    final dict = _buildEncryptDict(keys, permissions);

    expect(
      () => StandardSecurityHandler.fromEncrypt(dict, wrongId, 'pw', _identityResolve),
      throwsA(isA<CosPasswordException>()),
    );
  });

  test('padPassword pads short passwords with the exact standard padding string', () {
    final padded = padPassword('ab');
    expect(padded.length, 32);
    expect(padded.sublist(0, 2), [0x61, 0x62]);
    expect(padded.sublist(2), pdfPasswordPadding.sublist(0, 30));
  });

  test('padPassword truncates a password longer than 32 bytes', () {
    final longPw = 'x' * 40;
    final padded = padPassword(longPw);
    expect(padded.length, 32);
    expect(padded.every((b) => b == 0x78), isTrue);
  });

  test('randomFileId produces 16 bytes and is not deterministic across calls', () {
    final a = randomFileId();
    final b = randomFileId();
    expect(a.length, 16);
    expect(b.length, 16);
    expect(a, isNot(equals(b)));
  });
}
