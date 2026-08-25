import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pdf_cos/pdf_cos.dart' show rc4;

/// Computes the /O and /U entries and the file encryption key for a PDF
/// Standard Security Handler, revision 3 or 4 (ISO 32000-1 §7.6.3.3,
/// Algorithms 2/3/4/5) - the *write* side of the exact same algorithm
/// `package:pdf_cos`'s `StandardSecurityHandler` already implements
/// correctly for *reading* (`_computeClassicKey`/`_checkUser`/
/// `_authenticateClassic`, confirmed by direct source inspection). That
/// class's constructor is private and its one public factory
/// (`fromEncrypt`) only *authenticates against* an already-existing /O and
/// /U - there is no public "create encryption for a new password" entry
/// point in the library as published, so this module exists to compute
/// those values ourselves, using the library's own already-verified RC4
/// primitive (`rc4()`, exported from `pdf_cos.dart`) and `package:crypto`'s
/// MD5 (already a pinned dependency in this app) for every actual
/// cryptographic operation - this file never implements a cipher or hash
/// itself, only the PDF-specific algorithm that combines them.
///
/// Every step below cites the exact spec algorithm/sub-step it implements,
/// and every non-obvious asymmetry between [_computeOwnerKey] and
/// [computeFileKey] (which bytes get re-hashed on which iteration) was
/// checked line-by-line against `standard_security_handler.dart`'s own
/// reading implementation before being written - see the class doc comment
/// for how this module's correctness is independently cross-validated
/// against that reading implementation in `pdf_encryption_algorithms_test.dart`.
class PdfEncryptionKeys {
  const PdfEncryptionKeys({
    required this.fileKey,
    required this.o,
    required this.u,
  });

  final Uint8List fileKey;
  final Uint8List o;
  final Uint8List u;
}

/// PDF's standard 32-byte password padding string (ISO 32000-1 §7.6.3.3,
/// "PDF also defines a standard padding string"). A fixed, publicly
/// documented constant, not a secret.
final Uint8List pdfPasswordPadding = Uint8List.fromList([
  0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, //
  0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08, //
  0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80, //
  0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
]);

/// Pads/truncates [password] to exactly 32 bytes (Algorithm 2 step a /
/// Algorithm 3 step a): the password's own Latin-1 bytes, then as much of
/// the standard padding string as needed to reach 32.
Uint8List padPassword(String password) {
  final bytes = latin1.encode(password);
  final out = Uint8List(32);
  final n = math.min(32, bytes.length);
  out.setRange(0, n, bytes);
  out.setRange(n, 32, pdfPasswordPadding);
  return out;
}

/// Algorithm 3: computes /O from the owner password (or, when empty, the
/// user password stands in for it - the spec's own "if there is no owner
/// password, use the user password instead" rule) and the user password.
Uint8List computeO({
  required String userPassword,
  required String ownerPassword,
  required int lengthBits,
}) {
  final ownerPad = padPassword(ownerPassword.isEmpty ? userPassword : ownerPassword);
  // Steps b/c: MD5, then (revision >= 3) 50 more rounds hashing the *full*
  // previous 16-byte digest each time - deliberately not truncated to n
  // bytes per round here, unlike the file key's own 50-round loop below;
  // this asymmetry is real and was checked against the reference
  // implementation's own two (differently-shaped) loops.
  var hash = md5.convert(ownerPad).bytes;
  for (var i = 0; i < 50; i++) {
    hash = md5.convert(hash).bytes;
  }
  final n = (lengthBits ~/ 8).clamp(5, 16);
  final ownerKey = Uint8List.fromList(hash.sublist(0, n));

  // Steps e/f: RC4-encrypt the padded *user* password with ownerKey, then
  // (revision >= 3) 19 more passes with ownerKey's bytes XORed by the
  // round number.
  var result = rc4(ownerKey, padPassword(userPassword));
  for (var i = 1; i <= 19; i++) {
    final stepKey = [for (final b in ownerKey) b ^ i];
    result = rc4(stepKey, result);
  }
  return result;
}

/// Algorithm 2: computes the file encryption key from the user password,
/// the already-computed /O, the /P permission bits, and the file's /ID.
Uint8List computeFileKey({
  required String userPassword,
  required Uint8List o,
  required int permissionBits,
  required Uint8List firstId,
  required int lengthBits,
  bool encryptMetadata = true,
}) {
  final input = BytesBuilder()
    ..add(padPassword(userPassword))
    ..add(o.length >= 32 ? o.sublist(0, 32) : o)
    ..add([
      permissionBits & 0xFF,
      (permissionBits >> 8) & 0xFF,
      (permissionBits >> 16) & 0xFF,
      (permissionBits >> 24) & 0xFF,
    ])
    ..add(firstId);
  if (!encryptMetadata) {
    input.add([0xFF, 0xFF, 0xFF, 0xFF]);
  }
  var hash = md5.convert(input.takeBytes()).bytes;
  final n = (lengthBits ~/ 8).clamp(5, 16);
  // Step f: 50 more rounds, each hashing only the first n bytes of the
  // previous digest - the file key's own loop shape, distinct from /O's.
  for (var i = 0; i < 50; i++) {
    hash = md5.convert(hash.sublist(0, n)).bytes;
  }
  return Uint8List.fromList(hash.sublist(0, n));
}

/// Algorithm 5 (revision >= 3): computes /U from the file encryption key
/// and the file's /ID. Only the first 16 bytes are ever checked by a
/// reader (confirmed in `StandardSecurityHandler._checkUser`), so the
/// remaining 16 of the conventional 32-byte /U string are arbitrary -
/// zero-filled here, matching what most real-world encoders do.
Uint8List computeU({required Uint8List fileKey, required Uint8List firstId}) {
  final hash = md5.convert([...pdfPasswordPadding, ...firstId]).bytes;
  var cipher = rc4(fileKey, Uint8List.fromList(hash));
  for (var i = 1; i <= 19; i++) {
    final stepKey = [for (final b in fileKey) b ^ i];
    cipher = rc4(stepKey, cipher);
  }
  final u = Uint8List(32);
  u.setRange(0, 16, cipher);
  return u;
}

/// Computes everything a fresh /Encrypt dictionary needs for a chosen user
/// password (and optional owner password/permissions), revision 4
/// (`/V 4 /R 4`, the crypt-filter architecture AES-128 uses) at 128-bit
/// key length - the one configuration this app writes.
PdfEncryptionKeys computeEncryptionKeys({
  required String userPassword,
  String ownerPassword = '',
  required int permissionBits,
  required Uint8List firstId,
}) {
  const lengthBits = 128;
  final o = computeO(
    userPassword: userPassword,
    ownerPassword: ownerPassword,
    lengthBits: lengthBits,
  );
  final fileKey = computeFileKey(
    userPassword: userPassword,
    o: o,
    permissionBits: permissionBits,
    firstId: firstId,
    lengthBits: lengthBits,
  );
  final u = computeU(fileKey: fileKey, firstId: firstId);
  return PdfEncryptionKeys(fileKey: fileKey, o: o, u: u);
}

/// A cryptographically random 16-byte file /ID - generated once per
/// protected document, used both as the trailer's /ID and as an input to
/// [computeFileKey]/[computeU] (the spec requires the same bytes in both
/// places). Never derived from file content (unlike `CosDocumentBuilder`'s
/// own convenience default, an MD5 of the output bytes) because encryption
/// needs the ID to exist *before* the encrypted bytes it would otherwise be
/// hashed from.
Uint8List randomFileId() {
  final rng = math.Random.secure();
  return Uint8List.fromList([for (var i = 0; i < 16; i++) rng.nextInt(256)]);
}
