/// Barrel export for document text extraction (V2 scaffolding, Epic 2).
/// [OcrParser] is deliberately not exported here - it is out of scope for
/// V2 (ADR-015, docs/v2/implementation/03-decisions.md) and not part of
/// the active extraction pipeline.
library;

export 'document_text_extraction_service.dart';
export 'parsers/pdf_parser.dart';
export 'parsers/docx_parser.dart';
export 'parsers/text_markdown_parser.dart';
