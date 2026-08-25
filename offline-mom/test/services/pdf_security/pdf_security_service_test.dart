// Tests PdfSecurityService against REAL PDFs (built via the same
// PdfPageComposerService every other PDF Tool uses) and, critically,
// verifies the protected output *independently* - by re-opening it with
// pdf_cos's own CosDocument.open() directly, a wholly separate code path
// from PdfSecurityService's own protect()/removePassword() - not merely
// asserting this service's own claims about its own output.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/services/pdf_security/pdf_permissions.dart';
import 'package:offline_mom/services/pdf_security/pdf_security_service.dart';
import 'package:offline_mom/services/toolkit/pdf_page_composer.dart';
import 'package:pdf_cos/pdf_cos.dart';

Uint8List _photoJpeg({int width = 400, int height = 500}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(180, 200, 220));
  img.drawString(image, 'Confidential test content', font: img.arial24, x: 20, y: 20);
  return Uint8List.fromList(img.encodeJpg(image));
}

Future<Uint8List> _realPlainPdf({int pages = 1}) async {
  final composer = PdfPageComposerService();
  return composer.compose([
    for (var i = 0; i < pages; i++) PdfPageInput(jpegBytes: _photoJpeg(), width: 400, height: 500),
  ]);
}

void main() {
  const service = PdfSecurityService();

  group('protect', () {
    test('rejects an empty password (scenario: empty password)', () async {
      final plain = await _realPlainPdf();
      await expectLater(
        service.protect(plain, userPassword: ''),
        throwsA(isA<PdfSecurityException>()),
      );
    });

    test('produces real bytes that pdf_cos independently reports as encrypted (scenario: output actually encrypted)', () async {
      final plain = await _realPlainPdf();
      final protected = await service.protect(plain, userPassword: 'sesame123');

      final doc = CosDocument.open(protected, password: 'sesame123');
      expect(doc.isEncrypted, isTrue);
    });

    test('the correct password opens the protected PDF via an independent CosDocument.open call (scenario: correct password opens)', () async {
      final plain = await _realPlainPdf();
      final protected = await service.protect(plain, userPassword: 'right-password');

      expect(() => CosDocument.open(protected, password: 'right-password'), returnsNormally);
    });

    test('the wrong password is rejected, not silently accepted (scenario: incorrect password rejected)', () async {
      final plain = await _realPlainPdf();
      final protected = await service.protect(plain, userPassword: 'right-password');

      expect(
        () => CosDocument.open(protected, password: 'totally-wrong'),
        throwsA(isA<CosPasswordException>()),
      );
    });

    test('permissions actually decode from the real /P entry pdf_cos parses (scenario: permissions actually encoded)', () async {
      final plain = await _realPlainPdf();
      const chosen = PdfPermissions(allowCopying: false, allowPrinting: true, allowModify: false);
      final protected = await service.protect(plain, userPassword: 'pw', permissions: chosen);

      final doc = CosDocument.open(protected, password: 'pw');
      final encryptDict = doc.resolve(doc.trailer['Encrypt']) as CosDictionary;
      final p = (doc.resolve(encryptDict['P']) as CosInteger).value;
      final decoded = PdfPermissions.fromPBits(p);
      expect(decoded.allowCopying, isFalse);
      expect(decoded.allowModify, isFalse);
      expect(decoded.allowPrinting, isTrue);
    });

    test('the original plain bytes are never mutated (scenario: original file unchanged)', () async {
      final plain = await _realPlainPdf();
      final plainCopy = Uint8List.fromList(plain);
      await service.protect(plain, userPassword: 'pw');
      expect(plain, plainCopy);
    });

    test('page count is preserved for a multi-page PDF (scenario: multi-page PDF)', () async {
      final plain = await _realPlainPdf(pages: 5);
      final protected = await service.protect(plain, userPassword: 'pw');

      final doc = CosDocument.open(protected, password: 'pw');
      final pages = doc.resolve(doc.catalog['Pages']) as CosDictionary;
      final count = (doc.resolve(pages['Count']) as CosInteger).value;
      expect(count, 5);
    });

    test('a large (20-page) PDF protects and reopens correctly (scenario: large PDF)', () async {
      final plain = await _realPlainPdf(pages: 20);
      final protected = await service.protect(plain, userPassword: 'pw');

      final doc = CosDocument.open(protected, password: 'pw');
      final pages = doc.resolve(doc.catalog['Pages']) as CosDictionary;
      expect((doc.resolve(pages['Count']) as CosInteger).value, 20);
    });

    test('a corrupted PDF fails cleanly, not with a crash (scenario: corrupted PDF)', () async {
      final garbage = Uint8List.fromList([1, 2, 3, 4, 5]);
      await expectLater(
        service.protect(garbage, userPassword: 'pw'),
        throwsA(isA<PdfSecurityException>()),
      );
    });

    test('protecting an already-protected PDF fails cleanly instead of double-encrypting', () async {
      final plain = await _realPlainPdf();
      final protected = await service.protect(plain, userPassword: 'first');
      await expectLater(
        service.protect(protected, userPassword: 'second'),
        throwsA(isA<PdfSecurityException>()),
      );
    });

    test('an owner password separate from the user password both open the document', () async {
      final plain = await _realPlainPdf();
      final protected = await service.protect(
        plain,
        userPassword: 'user-pw',
        ownerPassword: 'owner-pw',
      );
      expect(() => CosDocument.open(protected, password: 'user-pw'), returnsNormally);
      expect(() => CosDocument.open(protected, password: 'owner-pw'), returnsNormally);
    });
  });

  group('inspect / checkPassword', () {
    test('reports an unencrypted PDF as not encrypted', () async {
      final plain = await _realPlainPdf();
      final info = service.inspect(plain);
      expect(info.isEncrypted, isFalse);
      expect(info.isCorrupted, isFalse);
    });

    test('reports a protected PDF as encrypted without needing the password', () async {
      final plain = await _realPlainPdf();
      final protected = await service.protect(plain, userPassword: 'pw');
      final info = service.inspect(protected);
      expect(info.isEncrypted, isTrue);
    });

    test('reports a corrupted file as corrupted, not encrypted', () {
      final info = service.inspect(Uint8List.fromList([9, 9, 9]));
      expect(info.isCorrupted, isTrue);
    });

    test('checkPassword validates the real password cryptographically', () async {
      final plain = await _realPlainPdf();
      final protected = await service.protect(plain, userPassword: 'correct');
      expect(service.checkPassword(protected, 'correct'), isTrue);
      expect(service.checkPassword(protected, 'incorrect'), isFalse);
    });
  });

  group('removePassword (Unlock)', () {
    test('unlocks with the correct password and the result is no longer encrypted (scenario: unlock with correct password)', () async {
      final plain = await _realPlainPdf();
      final protected = await service.protect(plain, userPassword: 'pw');

      final unlocked = await service.removePassword(protected, 'pw');

      final reopened = CosDocument.open(unlocked);
      expect(reopened.isEncrypted, isFalse);
    });

    test('rejects the wrong password with isWrongPassword, not a crash (scenario: unlock with incorrect password)', () async {
      final plain = await _realPlainPdf();
      final protected = await service.protect(plain, userPassword: 'pw');

      await expectLater(
        service.removePassword(protected, 'nope'),
        throwsA(isA<PdfSecurityException>().having((e) => e.isWrongPassword, 'isWrongPassword', isTrue)),
      );
    });

    test('unlocking preserves page count', () async {
      final plain = await _realPlainPdf(pages: 3);
      final protected = await service.protect(plain, userPassword: 'pw');
      final unlocked = await service.removePassword(protected, 'pw');

      final doc = CosDocument.open(unlocked);
      final pages = doc.resolve(doc.catalog['Pages']) as CosDictionary;
      expect((doc.resolve(pages['Count']) as CosInteger).value, 3);
    });

    test('the original protected bytes are never mutated by removePassword', () async {
      final plain = await _realPlainPdf();
      final protected = await service.protect(plain, userPassword: 'pw');
      final protectedCopy = Uint8List.fromList(protected);
      await service.removePassword(protected, 'pw');
      expect(protected, protectedCopy);
    });

    test('removePassword on an unencrypted PDF fails cleanly', () async {
      final plain = await _realPlainPdf();
      await expectLater(
        service.removePassword(plain, 'anything'),
        throwsA(isA<PdfSecurityException>()),
      );
    });
  });
}
