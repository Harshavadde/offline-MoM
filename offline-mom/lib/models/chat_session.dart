import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_session.freezed.dart';
part 'chat_session.g.dart';

/// Backed by `chat_sessions` (migration v9, V2 Phase 2A) - see
/// `docs/v2/12-database-design.md` and ADR-025
/// (docs/v2/implementation/03-decisions.md).

/// What a chat session is scoped to - resolves ADR-013
/// (docs/v2/implementation/03-decisions.md): one chat screen, one
/// [ChatSession] model, scope as data rather than three separate routes.
///
/// [meeting] was added in Phase 2A (ADR-025), absorbing what
/// `AskAboutMeetingsUseCase` previously handled as a separate feature
/// (ADR-010) - not part of `docs/v2/12-database-design.md`'s original
/// three-value list. [general] is not yet reachable from the chat UI
/// (M2.1, not Phase 2A) but stays defined so `chat_sessions.scope` never
/// needs another migration to add it later.
enum ChatScope { general, workspace, document, meeting }

@freezed
abstract class ChatSession with _$ChatSession {
  const ChatSession._();

  const factory ChatSession({
    required int? id,
    required String title,
    required ChatScope scope,
    required DateTime createdAt,
    required DateTime updatedAt,

    /// Set only when [scope] is [ChatScope.document] - per
    /// docs/v2/12-database-design.md's `chat_sessions.document_id`.
    int? documentId,

    /// Set only when [scope] is [ChatScope.meeting] - added in Phase 2A
    /// alongside [ChatScope.meeting] itself (ADR-025).
    int? meetingId,

    /// Added in migration v10 (V2 Phase 2B, ADR-028) - pinned conversations
    /// sort first in [ChatHistoryScreen], same convention as
    /// [Meeting.isFavorite].
    @Default(false) bool isPinned,
  }) = _ChatSession;

  factory ChatSession.fromJson(Map<String, Object?> json) =>
      _$ChatSessionFromJson(json);

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'scope': scope.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'document_id': documentId,
      'meeting_id': meetingId,
      'is_pinned': isPinned ? 1 : 0,
    };
  }

  factory ChatSession.fromMap(Map<String, Object?> map) {
    return ChatSession(
      id: map['id'] as int?,
      title: map['title'] as String,
      scope: ChatScope.values.byName(map['scope'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      documentId: map['document_id'] as int?,
      meetingId: map['meeting_id'] as int?,
      isPinned: (map['is_pinned'] as int? ?? 0) == 1,
    );
  }
}
