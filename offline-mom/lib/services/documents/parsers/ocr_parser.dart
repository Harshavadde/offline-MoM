/// V2 scaffolding for a capability that is explicitly OUT OF SCOPE for V2.
///
/// Per ADR-015 (docs/v2/implementation/03-decisions.md): V2 does not add
/// OCR. A PDF/DOCX with no extractable text layer (a scanned/image-only
/// document) surfaces a clear "no readable text found" error via the
/// normal `DocumentTextExtractionService` contract (extraction returns
/// null) - it does not fall back to this class.
///
/// This file exists only so the module boundary is reserved, per the
/// project's own future-roadmap note (docs/v2/20-future-roadmap.md) that
/// OCR is a plausible post-V2 candidate if user feedback shows the gap
/// matters in practice. It is NOT registered anywhere in the composition
/// root and NOT called by any parser above.
///
/// TODO(post-V2, not scheduled): if OCR is ever approved, implement this
/// as a real [DocumentTextExtractionService]-compatible fallback, invoked
/// by [PdfParser]/[DocxParser] only when their own extraction returns
/// null - see ADR-015 for the exact conditions this decision would need to
/// be revisited under.
class OcrParser {
  Future<String?> extractText(String filePath) {
    throw UnimplementedError(
      'OCR is out of scope for V2 - see ADR-015, '
      'docs/v2/implementation/03-decisions.md',
    );
  }
}
