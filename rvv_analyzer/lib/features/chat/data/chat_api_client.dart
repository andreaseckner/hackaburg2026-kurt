import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rvv_analyzer/features/chat/models/chat_response.dart';

class ChatApiClient {
  final http.Client _client;
  final Uri _chatUri;

  ChatApiClient({
    http.Client? client,
    String baseUrl = 'http://127.0.0.1:8123',
  })  : _client = client ?? http.Client(),
        _chatUri = Uri.parse('$baseUrl/chat/query');

  Future<ChatResponse> ask(String question) async {
    final response = await _client.post(
      _chatUri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'question': question}),
    );

    if (response.statusCode != 200) {
      throw Exception('Chat API failed: ${response.statusCode}');
    }

    return ChatResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
