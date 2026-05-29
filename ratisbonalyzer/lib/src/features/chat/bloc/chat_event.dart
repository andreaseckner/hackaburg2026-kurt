import 'package:equatable/equatable.dart';

abstract class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object?> get props => [];
}

class ChatQuestionSubmitted extends ChatEvent {
  final String question;

  const ChatQuestionSubmitted(this.question);

  @override
  List<Object?> get props => [question];
}

class ChatSuggestedQuestionSelected extends ChatEvent {
  final String question;

  const ChatSuggestedQuestionSelected(this.question);

  @override
  List<Object?> get props => [question];
}

class ChatCleared extends ChatEvent {
  const ChatCleared();
}
