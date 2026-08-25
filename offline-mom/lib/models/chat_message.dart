import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_message.freezed.dart';
part 'chat_message.g.dart';

/// Backed by `chat_messages` (migration v9, V2 Phase 2A) - see
/// `docs/v2/12-database-design.md` and ADR-025
/// (docs/v2/implementation/03-decisions.md).

enum ChatMessageRole { user, assistant }

/// Which prompt mode produced an assistant answer (Phase 6B, Hybrid
/// Retrieval Engine, ADR-037, docs/v2/implementation/03-decisions.md) -
/// see [ChatMessagesTable.answerProvenance]'s doc comment
/// (lib/database/tables.dart) for why this is persisted rather than
/// inferred from whether [ChatMessage.sourcesJson] is empty. Always null
/// for [ChatMessageRole.user] messages, and for any assistant message
/// persisted before this field existed (migration v14) - never assume
/// non-null.
enum AnswerProvenance {
  /// Answered from retrieved excerpts of the user's own meetings/documents
  /// ([LlmEngine.answerQuestionStream]).
  local,

  /// Hybrid retrieval found nothing confidently relevant, so the model
  /// answered from its own general knowledge instead
  /// ([LlmEngine.answerGeneralKnowledgeStream]) - the UI must label these
  /// distinctly ("This answer comes from the AI model's general
  /// knowledge", not "from your documents") and must never show source
  /// chips for them.
  generalKnowledge,
}

@freezed
abstract class ChatMessage with _$ChatMessage {
  const ChatMessage._();

  const factory ChatMessage({
    required int? id,
    required int sessionId,
    required ChatMessageRole role,
    required String content,
    required DateTime createdAt,

    /// Which meeting(s)/document(s) an assistant answer cited (FR-30,
    /// docs/v2/08-functional-requirements.md) - JSON-encoded list of
    /// [ChatSourceRef]s, built from the [KnowledgeChunk]s actually
    /// retrieved and included in the prompt's context, never parsed from
    /// the model's own text (ADR-026, docs/v2/implementation/03-decisions.md).
    /// Null for [ChatMessageRole.user] messages.
    String? sourcesJson,

    /// See [AnswerProvenance]. Null for [ChatMessageRole.user] messages
    /// and for any row written before migration v14.
    AnswerProvenance? answerProvenance,
  }) = _ChatMessage;

  factory ChatMessage.fromJson(Map<String, Object?> json) =>
      _$ChatMessageFromJson(json);

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'role': role.name,
      'content': content,
      'created_at': createdAt.toIso8601String(),
      'sources_json': sourcesJson,
      'answer_provenance': answerProvenance?.name,
    };
  }

  factory ChatMessage.fromMap(Map<String, Object?> map) {
    final rawProvenance = map['answer_provenance'] as String?;
    return ChatMessage(
      id: map['id'] as int?,
      sessionId: map['session_id'] as int,
      role: ChatMessageRole.values.byName(map['role'] as String),
      content: map['content'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      sourcesJson: map['sources_json'] as String?,
      answerProvenance: rawProvenance == null
          ? null
          : AnswerProvenance.values.byName(rawProvenance),
    );
  }
}
