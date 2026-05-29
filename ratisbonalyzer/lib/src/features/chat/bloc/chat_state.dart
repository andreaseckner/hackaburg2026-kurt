import 'package:equatable/equatable.dart';
import 'package:ratisbonalyzer/src/features/chat/models/chat_response.dart';

enum ChatStatus { initial, loading, loaded, error }

class ChatState extends Equatable {
  final ChatStatus status;
  final String currentQuestion;
  final ChatResponse? response;
  final String? errorMessage;

  const ChatState({
    this.status = ChatStatus.initial,
    this.currentQuestion = '',
    this.response,
    this.errorMessage,
  });

  ChatState copyWith({
    ChatStatus? status,
    String? currentQuestion,
    ChatResponse? response,
    String? errorMessage,
    bool clearResponse = false,
    bool clearError = false,
  }) {
    return ChatState(
      status: status ?? this.status,
      currentQuestion: currentQuestion ?? this.currentQuestion,
      response: clearResponse ? null : response ?? this.response,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, currentQuestion, response, errorMessage];
}
