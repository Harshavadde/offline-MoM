import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/friendly_error.dart';
import '../../../../providers/app_providers.dart';
import '../../ask_about_meetings_use_case.dart';

sealed class AskUiState {
  const AskUiState();
}

class AskIdle extends AskUiState {
  const AskIdle();
}

class AskLoading extends AskUiState {
  const AskLoading(this.question);
  final String question;
}

class AskAnswered extends AskUiState {
  const AskAnswered(this.question, this.answer);
  final String question;
  final AskAboutMeetingsAnswer answer;
}

class AskFailed extends AskUiState {
  const AskFailed(this.question, this.message);
  final String question;
  final String message;
}

class AskController extends Notifier<AskUiState> {
  @override
  AskUiState build() => const AskIdle();

  Future<void> ask(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty) return;

    state = AskLoading(trimmed);
    try {
      final answer = await ref.read(askAboutMeetingsUseCaseProvider)(trimmed);
      state = AskAnswered(trimmed, answer);
    } catch (e) {
      state = AskFailed(trimmed, friendlyErrorMessage(e));
    }
  }

  void reset() => state = const AskIdle();
}

final askControllerProvider = NotifierProvider<AskController, AskUiState>(AskController.new);
