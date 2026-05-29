import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ratisbonalyzer/src/features/chat/bloc/chat_event.dart';
import 'package:ratisbonalyzer/src/features/chat/bloc/chat_state.dart';
import 'package:ratisbonalyzer/src/features/chat/data/chat_api_client.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ChatApiClient _apiClient;

  ChatBloc({ChatApiClient? apiClient})
    : _apiClient = apiClient ?? ChatApiClient(),
      super(const ChatState()) {
    on<ChatQuestionSubmitted>(_onQuestionSubmitted);
    on<ChatSuggestedQuestionSelected>(_onSuggestedQuestionSelected);
    on<ChatCleared>(_onCleared);
  }

  Future<void> _onQuestionSubmitted(
    ChatQuestionSubmitted event,
    Emitter<ChatState> emit,
  ) async {
    final question = event.question.trim();
    if (question.isEmpty) {
      return;
    }

    emit(
      state.copyWith(
        status: ChatStatus.loading,
        currentQuestion: question,
        clearResponse: true,
        clearError: true,
      ),
    );

    try {
      final response = await _apiClient.ask(question);
      emit(
        state.copyWith(
          status: ChatStatus.loaded,
          response: response,
          clearError: true,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: ChatStatus.error,
          errorMessage: error.toString(),
          clearResponse: true,
        ),
      );
    }
  }

  Future<void> _onSuggestedQuestionSelected(
    ChatSuggestedQuestionSelected event,
    Emitter<ChatState> emit,
  ) async {
    add(ChatQuestionSubmitted(event.question));
  }

  void _onCleared(ChatCleared event, Emitter<ChatState> emit) {
    emit(const ChatState());
  }
}
