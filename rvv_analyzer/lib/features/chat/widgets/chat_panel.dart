import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rvv_analyzer/features/chat/bloc/chat_bloc.dart';
import 'package:rvv_analyzer/features/chat/bloc/chat_event.dart';
import 'package:rvv_analyzer/features/chat/bloc/chat_state.dart';
import 'package:rvv_analyzer/features/chat/models/chat_response.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key});

  static const suggestedQuestions = [
    'Where should we intervene first on weekday mornings?',
    'Which segment creates the most delay toward the city center?',
    'Which stops expose passengers to the most delay after 16:00?',
  ];

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: BlocBuilder<ChatBloc, ChatState>(
        builder: (context, state) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Reliability question',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Ask a supported reliability question',
                ),
                onSubmitted: (_) => _submit(context),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: state.status == ChatStatus.loading
                      ? null
                      : () => _submit(context),
                  icon: const Icon(Icons.send),
                  label: const Text('Ask'),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ChatPanel.suggestedQuestions.map((question) {
                  return ActionChip(
                    label: Text(question),
                    onPressed: state.status == ChatStatus.loading
                        ? null
                        : () {
                            _controller.text = question;
                            context.read<ChatBloc>().add(
                                  ChatSuggestedQuestionSelected(question),
                                );
                          },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              if (state.status == ChatStatus.loading)
                const Center(child: CircularProgressIndicator()),
              if (state.status == ChatStatus.error && state.errorMessage != null)
                Text(
                  state.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (state.status == ChatStatus.loaded && state.response != null)
                _AnswerCard(response: state.response!),
            ],
          );
        },
      ),
    );
  }

  void _submit(BuildContext context) {
    context.read<ChatBloc>().add(ChatQuestionSubmitted(_controller.text));
  }
}

class _AnswerCard extends StatelessWidget {
  final ChatResponse response;

  const _AnswerCard({required this.response});

  @override
  Widget build(BuildContext context) {
    final isUnsupported = response.intent == 'unsupported';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              response.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(response.answer),
            if (response.bullets.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...response.bullets.map((bullet) => Text('• $bullet')),
            ],
            const SizedBox(height: 8),
            Text(
              'Metric source: ${response.metricSource}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (isUnsupported && response.unsupportedReason != null) ...[
              const SizedBox(height: 8),
              Text(response.unsupportedReason!),
            ],
          ],
        ),
      ),
    );
  }
}
