import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

import 'pdf_encryption_algorithms.dart';
import 'pdf_permissions.dart';

class PdfSecurityException implements Exception {
  const PdfSecurityException(this.message, {this.isWrongPassword = false});
  final String message;

  /// True specifically for "the password you entered is wrong" - callers
  /// use this to show "Incorrect password." rather than a generic failure
  /// message, and to know the operation is safely retriable with a
  /// different password rather than failed outright.
  final bool isWrongPassword;

  @override
  String toString() => message;
}

/// What [PdfSecurityService.inspect] found about a PDF, without needing (or
/// attempting) to decrypt anything - a cheap, safe first look before ever
/// asking the user for a password.
class PdfSecurityInfo {
  const PdfSecurityInfo({required this.isEncrypted, this.isCorrupted = false});
  final bool isEncrypted;
  final bool isCorrupted;
}

/// Real, on-device PDF password protection - genuine PDF Standard Security
/// Handler revision 4 encryption (AES-128, ISO 32000-1 §7.6), not a visual
/// overlay or a renamed file. See ADR-046 (docs/v2/implementation/
/// 03-decisions.md) for why `pdf_cos`/`pdf_document` were added specifically
/// for this - `package:pdf` (this app's existing PDF writer, every other
/// Toolkit feature) ships no concrete encryption implementation at all.
///
/// [protect] always performs a *full, non-incremental* rewrite: every
/// object is read from the plain source document and re-serialized fresh
/// under the new encryption. This matters for real security, not just
/// correctness - an *incremental* update that merely appended an /Encrypt
/// dictionary to an existing file would leave the original plaintext
/// object bytes still physically present earlier in the same file,
/// trivially recoverable with any PDF repair tool. A full rewrite never
/// writes a plaintext byte of page content anywhere in the output.
class PdfSecurityService {
  const PdfSecurityService();

  /// Cheap, password-free check: is [bytes] a readable PDF, and is it
  /// encrypted? Used before ever prompting for a password (View PDF, P0-8
  /// Phase 8) - attempting the real native rasterization pipeline on an
  /// encrypted PDF first would surface a confusing generic failure instead
  /// of "This PDF is password protected."
  PdfSecurityInfo inspect(Uint8List bytes) {
    try {
      final doc = CosDocument.open(bytes);
      return PdfSecurityInfo(isEncrypted: doc.isEncrypted);
    } on CosPasswordException {
      // Opening with no password failed specifically because one is
      // required - definitively encrypted.
      return const PdfSecurityInfo(isEncrypted: true);
    } catch (_) {
      return const PdfSecurityInfo(isEncrypted: false, isCorrupted: true);
    }
  }

  /// Cryptographically validates [password] against [bytes]' real /O and
  /// /U entries (ISO 32000-1 Algorithm 6/7) - a genuine check, not a UI-only
  /// gate. Returns true only if the password actually opens the document.
  bool checkPassword(Uint8List bytes, String password) {
    try {
      CosDocument.open(bytes, password: password);
      return true;
    } on CosPasswordException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Encrypts [plainBytes] with [userPassword] (required, non-empty) and an
  /// optional, separate [ownerPassword] (defaults to the user password, per
  /// the PDF spec's own "no owner password" convention), applying
  /// [permissions]. Throws [PdfSecurityException] for an empty password, an
  /// already-encrypted source, or a corrupted/unreadable source - never
  /// silently produces a broken or unencrypted "protected" file.
  Future<Uint8List> protect(
    Uint8List plainBytes, {
    required String userPassword,
    String ownerPassword = '',
    PdfPermissions permissions = const PdfPermissions(),
  }) async {
    if (userPassword.isEmpty) {
      throw const PdfSecurityException('Enter a password.');
    }

    final CosDocument doc;
    try {
      doc = CosDocument.open(plainBytes);
    } on CosPasswordException {
      throw const PdfSecurityException('This PDF is already password protected.');
    } catch (_) {
      throw const PdfSecurityException('This PDF could not be read - it may be corrupted.');
    }
    if (doc.isEncrypted) {
      throw const PdfSecurityException('This PDF is already password protected.');
    }

    final fileId = randomFileId();
    final permissionBits = permissions.toPBits();
    final keys = computeEncryptionKeys(
      userPassword: userPassword,
      ownerPassword: ownerPassword,
      permissionBits: permissionBits,
      firstId: fileId,
    );

    final encryptDict = CosDictionary({
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
    final handler = StandardSecurityHandler.fromEncrypt(
      encryptDict,
      fileId,
      userPassword,
      doc.resolve,
    );

    final encrypted = <int, ({int generation, CosObject object})>{};
    var maxObjectNumber = 0;
    for (final number in doc.objectNumbers) {
      final entry = doc.xrefEntry(number);
      if (entry == null || entry.type == CosXrefEntryType.free) continue;
      if (number > maxObjectNumber) maxObjectNumber = number;
      final object = doc.getObject(number, entry.generation);
      if (object is CosNull) continue;
      final copy = handler.encryptObjectGraph(
        object,
        number,
        entry.generation,
        resolve: doc.resolve,
        keepsFileCiphertext: (_) => false,
      );
      encrypted[number] = (generation: entry.generation, object: copy);
    }

    final encryptObjectNumber = maxObjectNumber + 1;
    encrypted[encryptObjectNumber] = (generation: 0, object: encryptDict);

    return _writeFullRewrite(
      objects: encrypted,
      rootRef: doc.trailer['Root'] as CosReference,
      infoRef: doc.trailer['Info'] is CosReference ? doc.trailer['Info'] as CosReference : null,
      encryptRef: CosReference(encryptObjectNumber, 0),
      fileId: fileId,
    );
  }

  /// Decrypts a password-protected PDF into a brand-new, fully unencrypted
  /// copy - never modifies [protectedBytes]. Every string/stream is
  /// genuinely decrypted (not merely re-flagged as plain); the output flows
  /// through the exact same rasterization/search/OCR pipeline as any other
  /// plain PDF this app produces.
  Future<Uint8List> removePassword(Uint8List protectedBytes, String password) async {
    final CosDocument doc;
    try {
      doc = CosDocument.open(protectedBytes, password: password);
    } on CosPasswordException {
      throw const PdfSecurityException('Incorrect password.', isWrongPassword: true);
    } on UnsupportedEncryptionException catch (e) {
      throw PdfSecurityException('This PDF uses an unsupported encryption method ($e).');
    } catch (_) {
      throw const PdfSecurityException('This PDF could not be read - it may be corrupted.');
    }
    if (!doc.isEncrypted) {
      throw const PdfSecurityException('This PDF is not password protected.');
    }

    final objects = <int, ({int generation, CosObject object})>{};
    for (final number in doc.objectNumbers) {
      if (number == doc.encryptObjectNumber) continue;
      final entry = doc.xrefEntry(number);
      if (entry == null || entry.type == CosXrefEntryType.free) continue;
      final object = doc.getObject(number, entry.generation);
      if (object is CosNull) continue;
      // getObject() already returns strings decrypted; stream payloads
      // decrypt lazily via decodeStreamData, so re-materialize them decrypted
      // here rather than writing back the still-encrypted rawBytes.
      final resolved = _materializeDecryptedStreams(object, doc);
      objects[number] = (generation: entry.generation, object: resolved);
    }

    return _writeFullRewrite(
      objects: objects,
      rootRef: doc.trailer['Root'] as CosReference,
      infoRef: doc.trailer['Info'] is CosReference ? doc.trailer['Info'] as CosReference : null,
      encryptRef: null,
      fileId: randomFileId(),
    );
  }

  CosObject _materializeDecryptedStreams(CosObject object, CosDocument doc) {
    switch (object) {
      case CosStream():
        // Only decryption is undone here, not the rest of the filter chain
        // (Flate/etc. stays exactly as the source PDF encoded it) - mirrors
        // CosDocument's own _decodeStreamUncached decrypt-only step, which
        // is not itself public, so it's re-derived the same way here.
        final handler = doc.encryption;
        final owner = object.sourceRef;
        Uint8List payload = object.rawBytes;
        if (handler != null &&
            owner != null &&
            handler.streamPayloadIsEncrypted(object, doc.resolve)) {
          payload = handler.decryptStream(object.rawBytes, owner.objectNumber, owner.generation);
        }
        return CosStream(object.dictionary, payload);
      case CosArray():
        return CosArray([for (final item in object.items) _materializeDecryptedStreams(item, doc)]);
      case CosDictionary():
        final out = CosDictionary();
        object.entries.forEach((key, value) => out[key] = _materializeDecryptedStreams(value, doc));
        return out;
      default:
        return object;
    }
  }

  /// Writes a complete, from-scratch PDF file preserving each object's
  /// *original* object number (existing indirect references throughout the
  /// page tree point at those exact numbers) - the one capability neither
  /// `CosDocumentBuilder` (renumbers everything from 1, for genuinely new
  /// content) nor `CosIncrementalUpdater` (appends rather than rewriting,
  /// the exact plaintext-leakage risk this service must avoid) provides.
  /// Mirrors `CosDocumentBuilder`'s own classic-table output shape exactly
  /// (confirmed against its source), built from the same public
  /// `CosSerializer`/`CosXrefTableWriter` primitives it uses internally.
  Uint8List _writeFullRewrite({
    required Map<int, ({int generation, CosObject object})> objects,
    required CosReference rootRef,
    CosReference? infoRef,
    required CosReference? encryptRef,
    required Uint8List fileId,
  }) {
    final out = BytesBuilder(copy: false);
    out.add('%PDF-1.7\n'.codeUnits);
    out.add(const [0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);

    final serializer = CosSerializer(out);
    final offsets = <int, int>{};
    final numbers = objects.keys.toList()..sort();
    for (final number in numbers) {
      offsets[number] = out.length;
      final entry = objects[number]!;
      serializer.writeIndirectObject(CosIndirectObject(number, entry.generation, entry.object));
    }

    final tail = CosXrefTableWriter(out);
    final xrefOffset = out.length;
    tail.writeTable(
      offsets,
      (number) => objects[number]!.generation,
      includeFreeHead: true,
    );

    final trailer = CosDictionary({
      'Size': CosInteger((numbers.isEmpty ? 0 : numbers.last) + 1),
      'Root': rootRef,
      if (infoRef != null) 'Info': infoRef,
      if (encryptRef != null) 'Encrypt': encryptRef,
      'ID': CosArray([CosString(fileId, isHex: true), CosString(fileId, isHex: true)]),
    });
    tail.writeTrailer(trailer);
    tail.writeEpilogue(xrefOffset);
    return out.toBytes();
  }
}
