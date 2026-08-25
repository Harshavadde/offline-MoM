import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/retrieval/chunking_service.dart';

void main() {
  test('returns no chunks for empty or whitespace-only text', () {
    const service = DefaultChunkingService();
    expect(service.chunk(''), isEmpty);
    expect(service.chunk('   \n\n  '), isEmpty);
  });

  test('short text becomes a single chunk', () {
    const service = DefaultChunkingService();
    final chunks = service.chunk('This is a short sentence. Here is another.');
    expect(chunks, hasLength(1));
    expect(chunks.single.index, 0);
    expect(chunks.single.text, contains('This is a short sentence.'));
    expect(chunks.single.text, contains('Here is another.'));
  });

  test('chunk indices are sequential starting at 0', () {
    const service = DefaultChunkingService(targetChunkChars: 20, overlapSentences: 0);
    final chunks = service.chunk(
      'First sentence here. Second sentence here. Third sentence here. '
      'Fourth sentence here.',
    );
    expect(chunks.length, greaterThan(1));
    expect(chunks.map((c) => c.index), List.generate(chunks.length, (i) => i));
  });

  test('splits into multiple chunks once the character budget is exceeded',
      () {
    const service = DefaultChunkingService(targetChunkChars: 30, overlapSentences: 0);
    final chunks = service.chunk(
      'Alpha sentence number one. Beta sentence number two. '
      'Gamma sentence number three. Delta sentence number four.',
    );
    expect(chunks.length, greaterThan(1));
    for (final chunk in chunks) {
      expect(chunk.text, isNotEmpty);
    }
  });

  test('consecutive chunks overlap by the configured number of trailing '
      'sentences', () {
    const service = DefaultChunkingService(targetChunkChars: 25, overlapSentences: 1);
    final chunks = service.chunk(
      'Sentence one is here. Sentence two is here. Sentence three is here.',
    );
    expect(chunks.length, greaterThanOrEqualTo(2));
    // The last sentence of chunk N should also open chunk N+1.
    for (var i = 0; i < chunks.length - 1; i++) {
      final lastSentenceOfCurrent = chunks[i].text.split('. ').last;
      expect(chunks[i + 1].text, contains(lastSentenceOfCurrent.replaceAll('.', '')));
    }
  });

  test('a single sentence longer than the target budget still becomes its '
      'own chunk rather than being hard-cut mid-sentence', () {
    const service = DefaultChunkingService(targetChunkChars: 10, overlapSentences: 0);
    const longSentence = 'This one sentence is deliberately much longer than the target chunk budget.';
    final chunks = service.chunk(longSentence);
    expect(chunks, hasLength(1));
    expect(chunks.single.text, longSentence);
  });

  test('respects paragraph boundaries as well as sentence boundaries', () {
    const service = DefaultChunkingService();
    final chunks = service.chunk(
      'Paragraph one, sentence one.\n\nParagraph two, sentence one.',
    );
    expect(chunks, hasLength(1));
    expect(chunks.single.text, contains('Paragraph one'));
    expect(chunks.single.text, contains('Paragraph two'));
  });

  test('handles a very large document without truncation (all text is '
      'preserved across chunks)', () {
    const service = DefaultChunkingService();
    final sentences = List.generate(500, (i) => 'This is sentence number $i in a long document.');
    final text = sentences.join(' ');

    final chunks = service.chunk(text);

    expect(chunks.length, greaterThan(1));
    final recombined = chunks.map((c) => c.text).join(' ');
    for (var i = 0; i < 500; i += 50) {
      expect(recombined, contains('sentence number $i'));
    }
  });
}
