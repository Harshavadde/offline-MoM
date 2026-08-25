import '../../repositories/chat_session_repository.dart';

/// Deletes a chat conversation (FR-33, docs/v2/08-functional-requirements.md).
/// Mirrors `DeleteMeetingUseCase`'s simplicity - `chat_messages.session_id`'s
/// `ON DELETE CASCADE` (migration v9) removes the session's messages
/// automatically, so this only needs to delete the session row itself.
class DeleteChatSessionUseCase {
  DeleteChatSessionUseCase({required ChatSessionRepository chatSessionRepository})
      : _chatSessionRepository = chatSessionRepository;

  final ChatSessionRepository _chatSessionRepository;

  Future<void> call(int sessionId) {
    return _chatSessionRepository.delete(sessionId);
  }
}
