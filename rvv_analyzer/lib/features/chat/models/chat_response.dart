class ChatResponse {
  final String intent;
  final double confidence;
  final String title;
  final String answer;
  final List<String> bullets;
  final String metricSource;
  final List<dynamic> data;
  final Map<String, dynamic>? mapState;
  final List<String> suggestedQuestions;
  final String? unsupportedReason;

  const ChatResponse({
    required this.intent,
    required this.confidence,
    required this.title,
    required this.answer,
    required this.bullets,
    required this.metricSource,
    required this.data,
    required this.mapState,
    required this.suggestedQuestions,
    required this.unsupportedReason,
  });

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    return ChatResponse(
      intent: json['intent'] as String? ?? 'unsupported',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      title: json['title'] as String? ?? '',
      answer: json['answer'] as String? ?? '',
      bullets: (json['bullets'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
      metricSource: json['metric_source'] as String? ?? 'none',
      data: json['data'] as List<dynamic>? ?? const [],
      mapState: json['map_state'] as Map<String, dynamic>?,
      suggestedQuestions:
          (json['suggested_questions'] as List<dynamic>? ?? [])
              .map((item) => item.toString())
              .toList(),
      unsupportedReason: json['unsupported_reason'] as String?,
    );
  }
}
