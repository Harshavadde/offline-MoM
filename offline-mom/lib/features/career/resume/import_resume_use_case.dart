import '../../../models/document.dart';
import '../../../models/resume.dart';
import '../../../models/resume_block_type.dart';
import '../../../repositories/certification_block_repository.dart';
import '../../../repositories/custom_section_block_repository.dart';
import '../../../repositories/education_block_repository.dart';
import '../../../repositories/experience_block_repository.dart';
import '../../../repositories/project_block_repository.dart';
import '../../../repositories/resume_block_repository.dart';
import '../../../repositories/resume_repository.dart';
import '../../../repositories/skill_entry_repository.dart';
import '../../../services/documents/document_text_extraction_service.dart';
import '../../../services/resume/resume_import_parser.dart';

/// Thrown when the extraction step itself cannot produce usable text for
/// import - no extractor registered for the format, or extraction
/// succeeded but found nothing readable (a scanned/image-only PDF, or a
/// genuinely empty document). Distinct from the typed exceptions the
/// underlying `DocumentTextExtractionService` implementations already
/// throw (`PdfReadException`/`DocxReadException`) - those mean "this file
/// could not be read at all" and are left to propagate unchanged, since
/// they already carry a specific, user-safe message; this one means "the
/// file was read fine, but has nothing import can work with."
class ResumeImportExtractionException implements Exception {
  ResumeImportExtractionException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Orchestrates the two halves of resume import that Batch 7's own target
/// flow ("IMPORT -> EXTRACT -> STRUCTURE -> EDIT -> REGENERATE") treats as
/// distinct, user-visible steps rather than one atomic action:
///
/// 1. [extractAndParse] - format-specific text extraction (reusing the
///    same `DocumentTextExtractionService` implementations/DI map the
///    Documents feature already registers - `PdfParser`/`DocxParser`/
///    `TextMarkdownParser`, entirely unmodified) followed by
///    [ResumeImportParser.parse]. Touches no repository at all - nothing
///    is persisted yet, so the user can review before anything is written.
/// 2. [confirmImport] - only called once the user has reviewed the draft
///    and confirmed it. Creates the [Resume] row and, for each detected
///    library block, inserts it into its own repository and attaches it to
///    the new resume via [ResumeBlockRepository.attach] - the exact same
///    repositories and attach contract Batch 5's Editor already uses, so
///    an imported resume is, from this point on, completely
///    indistinguishable from one built by hand.
///
/// Crosses six repositories, the same "earns a dedicated use case"
/// reasoning `DeleteResumeUseCase` already documents for its own
/// multi-repository orchestration.
class ImportResumeUseCase {
  ImportResumeUseCase({
    required Map<DocumentSourceType, DocumentTextExtractionService> extractors,
    required ResumeImportParser parser,
    required ResumeRepository resumeRepository,
    required ResumeBlockRepository resumeBlockRepository,
    required ExperienceBlockRepository experienceBlockRepository,
    required EducationBlockRepository educationBlockRepository,
    required ProjectBlockRepository projectBlockRepository,
    required CertificationBlockRepository certificationBlockRepository,
    required SkillEntryRepository skillEntryRepository,
    required CustomSectionBlockRepository customSectionBlockRepository,
  })  : _extractors = extractors,
        _parser = parser,
        _resumeRepository = resumeRepository,
        _resumeBlockRepository = resumeBlockRepository,
        _experienceBlockRepository = experienceBlockRepository,
        _educationBlockRepository = educationBlockRepository,
        _projectBlockRepository = projectBlockRepository,
        _certificationBlockRepository = certificationBlockRepository,
        _skillEntryRepository = skillEntryRepository,
        _customSectionBlockRepository = customSectionBlockRepository;

  final Map<DocumentSourceType, DocumentTextExtractionService> _extractors;
  final ResumeImportParser _parser;
  final ResumeRepository _resumeRepository;
  final ResumeBlockRepository _resumeBlockRepository;
  final ExperienceBlockRepository _experienceBlockRepository;
  final EducationBlockRepository _educationBlockRepository;
  final ProjectBlockRepository _projectBlockRepository;
  final CertificationBlockRepository _certificationBlockRepository;
  final SkillEntryRepository _skillEntryRepository;
  final CustomSectionBlockRepository _customSectionBlockRepository;

  /// Extracts and structures [filePath] without persisting anything.
  /// Throws [ResumeImportExtractionException] if nothing readable was
  /// found; lets the extractor's own typed read-failure exception
  /// (`PdfReadException`/`DocxReadException`) propagate unchanged for a
  /// genuinely unreadable file.
  Future<ParsedResumeDraft> extractAndParse(String filePath, DocumentSourceType sourceType) async {
    final extractor = _extractors[sourceType];
    if (extractor == null) {
      // Can't happen with the current fixed set of DocumentSourceType
      // values and this use case's own DI wiring, which registers every
      // value - guarded anyway so an extractor map gap fails loudly and
      // diagnosably rather than with a raw null-check error, mirroring
      // `ExtractDocumentTextUseCase`'s identical guard.
      throw ResumeImportExtractionException(
        'Importing .${sourceType.name} files is not supported.',
      );
    }

    final text = await extractor.extractText(filePath);
    if (text == null) {
      throw ResumeImportExtractionException(
        sourceType == DocumentSourceType.pdf
            ? 'This PDF has no extractable text - it may be a scanned or '
                'image-only document. Scanned-document import is not '
                'supported yet.'
            : 'No readable text was found in this file.',
      );
    }

    return _parser.parse(text);
  }

  /// Persists [draft] as a new [Resume] with [title], plus one library
  /// block per detected entry, each attached to the new resume. Returns
  /// the new resume's id.
  Future<int> confirmImport(ParsedResumeDraft draft, {required String title}) async {
    final now = DateTime.now();
    final resumeId = await _resumeRepository.insert(Resume(
      id: null,
      title: title,
      fullName: draft.fullName ?? '',
      email: draft.email,
      phone: draft.phone,
      location: draft.location,
      links: draft.links,
      createdAt: now,
      updatedAt: now,
    ));

    for (final block in draft.experience) {
      final blockId = await _experienceBlockRepository.insert(block);
      await _resumeBlockRepository.attach(resumeId, ResumeBlockType.experience, blockId);
    }
    for (final block in draft.education) {
      final blockId = await _educationBlockRepository.insert(block);
      await _resumeBlockRepository.attach(resumeId, ResumeBlockType.education, blockId);
    }
    for (final block in draft.projects) {
      final blockId = await _projectBlockRepository.insert(block);
      await _resumeBlockRepository.attach(resumeId, ResumeBlockType.project, blockId);
    }
    for (final block in draft.certifications) {
      final blockId = await _certificationBlockRepository.insert(block);
      await _resumeBlockRepository.attach(resumeId, ResumeBlockType.certification, blockId);
    }
    for (final block in draft.skills) {
      final blockId = await _skillEntryRepository.insert(block);
      await _resumeBlockRepository.attach(resumeId, ResumeBlockType.skill, blockId);
    }
    // Beta data-fidelity requirement (docs/v3/implementation/03-decisions.md):
    // any section the parser recognized a header for but has no dedicated
    // typed field for (Awards, Publications, Volunteer Experience, ...)
    // still gets persisted and attached here, exactly like every other
    // block type - never dropped just because this app has no special
    // layout for it.
    for (final block in draft.customSections) {
      final blockId = await _customSectionBlockRepository.insert(block);
      await _resumeBlockRepository.attach(resumeId, ResumeBlockType.customSection, blockId);
    }

    return resumeId;
  }
}
