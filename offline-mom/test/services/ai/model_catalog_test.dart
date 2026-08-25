import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/ai/model_catalog.dart';
import 'package:offline_mom/services/ai/model_lifecycle_manager.dart';

void main() {
  group('ModelCatalog', () {
    test('every catalog entry has a unique id', () {
      final ids = ModelCatalog.all.map((m) => m.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every kind with catalog entries has exactly one default', () {
      for (final kind in ModelKind.values) {
        final entries = ModelCatalog.forKind(kind);
        if (entries.isEmpty) continue;
        final defaults = entries.where((m) => m.isDefault).toList();
        expect(defaults.length, 1, reason: '$kind should have exactly one default entry');
      }
    });

    test('vision and translation have zero catalog entries (future-ready, not built)', () {
      expect(ModelCatalog.forKind(ModelKind.vision), isEmpty);
      expect(ModelCatalog.forKind(ModelKind.translation), isEmpty);
      expect(ModelCatalog.defaultFor(ModelKind.vision), isNull);
      expect(ModelCatalog.defaultFor(ModelKind.translation), isNull);
    });

    test('ocr has exactly one catalog entry today (P0-7: English, ADR-045)', () {
      expect(ModelCatalog.forKind(ModelKind.ocr), hasLength(1));
      expect(ModelCatalog.defaultFor(ModelKind.ocr)?.id, ModelCatalog.ocrEnglish.id);
    });

    test('embedding has exactly one catalog entry today (ADR-036)', () {
      expect(ModelCatalog.forKind(ModelKind.embedding), hasLength(1));
    });

    test('llm has exactly two catalog entries: the required baseline plus the optional '
        'Milestone 4 upgrade tier (docs/v3/01-prd.md §13/§25)', () {
      expect(ModelCatalog.forKind(ModelKind.llm), hasLength(2));
    });

    test('exactly one llm entry is the default, and it is the original baseline model - the '
        'Milestone 4 upgrade tier must never become the default (FR3-16)', () {
      final llmEntries = ModelCatalog.forKind(ModelKind.llm);
      final defaults = llmEntries.where((m) => m.isDefault).toList();
      expect(defaults, hasLength(1));
      expect(defaults.single.id, ModelCatalog.llmQwen25_1_5b.id);
    });

    test('speechToText offers all 6 real WhisperModel sizes', () {
      expect(ModelCatalog.forKind(ModelKind.speechToText), hasLength(6));
    });

    test('byId resolves a known id and returns null for an unknown one', () {
      expect(ModelCatalog.byId(ModelCatalog.whisperSmall.id), same(ModelCatalog.whisperSmall));
      expect(ModelCatalog.byId('does-not-exist'), isNull);
    });

    test('defaultFor(speechToText) is Small, matching the pre-Phase-6A default', () {
      expect(ModelCatalog.defaultFor(ModelKind.speechToText)?.id, ModelCatalog.whisperSmall.id);
    });

    test('every entry has a positive approximate size and RAM requirement', () {
      for (final spec in ModelCatalog.all) {
        expect(spec.sizeBytesApprox, greaterThan(0));
        expect(spec.ramRequirementMb, greaterThan(0));
      }
    });

    test(
      'Physical-Mobile-First Validation phase (final beta build): every llm/embedding entry '
      'downloads a GGUF source and every speechToText entry downloads a whisper.cpp ggml '
      '.bin source - never a LiteRT-LM (.litertlm) source. This is the actual safety '
      'invariant behind pubspec.yaml\'s hooks.user_defines.llamadart.llamadart_native_runtimes: '
      '[llama_cpp] restriction (which drops LiteRT-LM\'s native libraries from the built APK '
      'entirely, ~46MB smaller arm64-v8a release - see docs/v3/implementation/03-decisions.md) - '
      'if a future model addition ever needs LiteRT-LM, that pubspec restriction must be '
      'revisited *before* the model ships, not discovered as a runtime crash on a real device. '
      'This test is the tripwire for that.',
      () {
        for (final spec in ModelCatalog.forKind(ModelKind.llm)) {
          expect(spec.downloadSource, endsWith('.gguf'), reason: spec.id);
        }
        for (final spec in ModelCatalog.forKind(ModelKind.embedding)) {
          expect(spec.downloadSource, endsWith('.gguf'), reason: spec.id);
        }
        for (final spec in ModelCatalog.forKind(ModelKind.speechToText)) {
          expect(spec.downloadSource, endsWith('.bin'), reason: spec.id);
          expect(spec.downloadSource, contains('whisper.cpp'), reason: spec.id);
        }
        for (final spec in ModelCatalog.all) {
          expect(spec.downloadSource.toLowerCase(), isNot(contains('litert')), reason: spec.id);
          expect(spec.downloadSource.toLowerCase(), isNot(contains('.tflite')), reason: spec.id);
        }
      },
    );
  });
}
