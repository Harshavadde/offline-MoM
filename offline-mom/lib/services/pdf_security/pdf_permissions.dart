/// PDF Standard Security Handler permission flags (ISO 32000-1 §7.6.3.2,
/// Table 22) - what the /P entry in an /Encrypt dictionary actually encodes.
/// Every bit position below is a direct transcription of that table, not a
/// guess: bit 1 is the least-significant bit, bits 1-2 are always reserved
/// (must be 0), and for a revision-3-or-later handler (this app only ever
/// writes revision 4) bits 11-32 are reserved and must be 1. A permission
/// this class doesn't expose (e.g. "extract for accessibility", bit 8) is
/// left permanently allowed (1) rather than force-denied, matching every
/// mainstream PDF tool's own default and avoiding a UI control this app has
/// no way to explain the effect of.
class PdfPermissions {
  const PdfPermissions({
    this.allowPrinting = true,
    this.allowHighQualityPrinting = true,
    this.allowCopying = true,
    this.allowModify = true,
    this.allowAnnotations = true,
  });

  /// Bit 3 - print the document at all.
  final bool allowPrinting;

  /// Bit 12 - print at full/high resolution rather than a low-res/degraded
  /// rendering. Meaningless (and left true, per spec) when [allowPrinting]
  /// is false - the encoder still writes it honestly, since a security
  /// handler that reports a permission it cannot enforce would be exactly
  /// the "expose options the library can't actually enforce" mistake this
  /// feature must avoid; the *bit* is always genuinely honored by any
  /// compliant reader even though this app never restricts print quality
  /// on its own.
  final bool allowHighQualityPrinting;

  /// Bit 5 - copy/extract text and graphics.
  final bool allowCopying;

  /// Bit 4 - modify the document's contents (not counting annotations/form
  /// fields, which bit 6 covers separately).
  final bool allowModify;

  /// Bit 6 - add or modify text annotations, and fill in form fields.
  final bool allowAnnotations;

  /// Encodes these flags into the /P integer a revision-4 (or later)
  /// Standard Security Handler expects: a 32-bit *signed* value, per
  /// ISO 32000-1 §7.6.3.2 - bits 1-2 always 0, bits 11-32 always 1 (the
  /// permanent "reserved" mask below), with bits 3-10 set according to the
  /// flags above (unset real-world-relevant bits like 7-10 default to
  /// allowed, matching every mainstream PDF tool).
  int toPBits() {
    // Bits 11-32 reserved=1, bits 1-2 reserved=0, bits 3-10 all
    // provisionally allowed (1) - this is the "grant everything" base every
    // real encoder starts from, then clears specific bits to deny.
    // 0xFFFFFFFC = bits 1-2 clear (0), bits 3-32 set (1).
    var bits = 0xFFFFFFFC;
    if (!allowPrinting) bits &= ~(1 << 2); // bit 3
    if (!allowModify) bits &= ~(1 << 3); // bit 4
    if (!allowCopying) bits &= ~(1 << 4); // bit 5
    if (!allowAnnotations) bits &= ~(1 << 5); // bit 6
    if (!allowHighQualityPrinting) bits &= ~(1 << 11); // bit 12
    // Reinterpret the low 32 bits as signed (PDF /P is a signed integer).
    return bits.toSigned(32);
  }

  /// Decodes a /P value back into flags - used when reporting an existing
  /// protected PDF's permissions to the user (Phase 2/permissions display),
  /// and by tests to round-trip [toPBits].
  factory PdfPermissions.fromPBits(int p) {
    final bits = p.toUnsigned(32);
    bool has(int bitNumber) => (bits & (1 << (bitNumber - 1))) != 0;
    return PdfPermissions(
      allowPrinting: has(3),
      allowHighQualityPrinting: has(12),
      allowCopying: has(5),
      allowModify: has(4),
      allowAnnotations: has(6),
    );
  }
}
