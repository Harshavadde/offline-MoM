import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../../models/document.dart';
import '../document_text_extraction_service.dart';

/// Thrown when the file isn't a valid DOCX (not a zip at all, or a zip
/// missing the `word/document.xml` every real .docx contains) - distinct
/// from [DocumentTextExtractionService.extractText] returning null (a
/// structurally valid but genuinely empty document), same distinction
/// [PdfReadException] draws for PDFs.
class DocxReadException implements Exception {
  DocxReadException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Hand-rolled on top of `archive` + `xml` (both MIT, both extremely
/// widely used - see ADR-016, docs/v2/implementation/03-decisions.md)
/// rather than depending on a thin, largely-unmaintained DOCX wrapper
/// package for something this small: a .docx is a zip archive containing
/// `word/document.xml`, itself a WordprocessingML document whose visible
/// text lives in `<w:t>` elements, grouped into `<w:p>` paragraphs.
class DocxParser implements DocumentTextExtractionService {
  @override
  DocumentSourceType get supportedSourceType => DocumentSourceType.docx;

  @override
  Future<String?> extractText(String filePath) async {
    final bytes = await File(filePath).readAsBytes();

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw DocxReadException(
        'This file is not a valid DOCX document (could not be read as a '
        'zip archive): $e',
      );
    }

    final documentXml = archive.findFile('word/document.xml');
    if (documentXml == null) {
      throw DocxReadException(
        'This file is not a valid DOCX document (missing '
        'word/document.xml).',
      );
    }

    final xmlBytes = documentXml.readBytes();
    if (xmlBytes == null) {
      throw DocxReadException(
        'This DOCX document\'s content could not be read.',
      );
    }

    final XmlDocument xmlDoc;
    try {
      xmlDoc = XmlDocument.parse(utf8.decode(xmlBytes));
    } catch (e) {
      throw DocxReadException('This DOCX document\'s content is not valid XML: $e');
    }

    final buffer = StringBuffer();
    for (final paragraph in xmlDoc.findAllElements('w:p')) {
      final paragraphText =
          paragraph.findAllElements('w:t').map((e) => e.innerText).join();
      // Every paragraph writes a line - including an empty one. A real
      // .docx resume typically separates entries (e.g. consecutive
      // Projects) with a blank spacing paragraph, not visible text; this
      // used to be dropped entirely (`if paragraphText.trim().isNotEmpty`),
      // which erased the blank-line boundary `ResumeImportParser`'s own
      // block-splitting relies on to tell two entries apart - multiple
      // projects/experience/education entries silently collapsed into one
      // block as a result (beta data-fidelity fix,
      // docs/v3/implementation/03-decisions.md). Writing the blank line
      // unconditionally restores that boundary exactly as `PdfParser`'s
      // own page-by-page text already preserves it.
      buffer.writeln(paragraphText);
    }

    final text = buffer.toString().trim();
    return text.isEmpty ? null : text;
  }
}
