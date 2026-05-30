import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ratisbonalyzer/src/features/chat/bloc/chat_bloc.dart';
import 'package:ratisbonalyzer/src/features/chat/bloc/chat_event.dart';
import 'package:ratisbonalyzer/src/features/chat/bloc/chat_state.dart';
import 'package:ratisbonalyzer/src/features/chat/models/chat_response.dart';

class ChatPanel extends StatefulWidget {
  final VoidCallback? onClose;
  final double height;

  const ChatPanel({super.key, this.onClose, this.height = 540});

  static const suggestedQuestions = [
    'Show me all delays from bus line 6 between 4pm and 6pm',
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
    return SizedBox(
      height: widget.height,
      child: Card(
        elevation: 8,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: BlocBuilder<ChatBloc, ChatState>(
            builder: (context, state) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Ask the reliability assistant',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close chat',
                        icon: const Icon(Icons.close),
                        onPressed: _close,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ask about stops, corridors, weekday mornings, delay hotspots, or specific dates.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: ChatPanel.suggestedQuestions.map((
                              question,
                            ) {
                              return ActionChip(
                                label: Text(question),
                                onPressed: state.status == ChatStatus.loading
                                    ? null
                                    : () {
                                        _controller.text = question;
                                        context.read<ChatBloc>().add(
                                          ChatSuggestedQuestionSelected(
                                            question,
                                          ),
                                        );
                                      },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                          if (state.status == ChatStatus.loading)
                            const Center(child: CircularProgressIndicator()),
                          if (state.status == ChatStatus.error &&
                              state.errorMessage != null)
                            Text(
                              state.errorMessage!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          if (state.status == ChatStatus.loaded &&
                              state.response != null)
                            _AnswerCard(response: state.response!),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 3,
                          textInputAction: TextInputAction.send,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'Ask me anything...',
                          ),
                          onSubmitted: (_) => _submit(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: state.status == ChatStatus.loading
                            ? null
                            : () => _submit(context),
                        child: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _close() {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
      return;
    }
    Navigator.of(context).maybePop();
  }

  void _submit(BuildContext context) {
    context.read<ChatBloc>().add(ChatQuestionSubmitted(_controller.text));
  }
}

class _PrimaryMetric extends StatelessWidget {
  final Map<String, dynamic> metric;

  const _PrimaryMetric({required this.metric});

  @override
  Widget build(BuildContext context) {
    final label = metric['label']?.toString() ?? 'Metric';
    final value = metric['value']?.toString() ?? '-';
    final unit = metric['unit']?.toString() ?? '';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value $unit',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            softWrap: true,
          ),
          const SizedBox(height: 4),
          Text(label, softWrap: true),
        ],
      ),
    );
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
            if (response.ui['primary_metric'] is Map<String, dynamic>) ...[
              const SizedBox(height: 8),
              _PrimaryMetric(
                metric: response.ui['primary_metric'] as Map<String, dynamic>,
              ),
            ],
            if (response.bullets.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Top bullets:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              ...response.bullets.map((bullet) => Text('- $bullet')),
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
