import 'dart:convert';

import 'package:deepseek_function_call_example/core/config/locator.dart';
import 'package:deepseek_function_call_example/presentation/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deepseek/flutter_deepseek.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Answers each request from [handler] and records the request bodies.
class FakeHttpClient extends http.BaseClient {
  FakeHttpClient(this.handler);

  final Map<String, dynamic> Function(String path, Map<String, dynamic> body)
  handler;
  final requests = <(String, Map<String, dynamic>)>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body =
        jsonDecode((request as http.Request).body) as Map<String, dynamic>;
    requests.add((request.url.path, body));
    final bytes = utf8.encode(jsonEncode(handler(request.url.path, body)));
    return http.StreamedResponse(
      Stream.value(bytes),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

Map<String, dynamic> completion(Map<String, dynamic> message) => {
  'id': 'x',
  'created': 1,
  'choices': [
    {'index': 0, 'finish_reason': 'stop', 'message': message},
  ],
};

void main() {
  late FakeHttpClient fake;

  Future<void> pumpScreen(WidgetTester tester) async {
    await locator.reset();
    locator.registerSingleton(DeepSeekClient(apiKey: 'k', httpClient: fake));
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
  }

  tearDown(() => locator.reset());

  testWidgets('shows the welcome text before any message', (tester) async {
    fake = FakeHttpClient((_, _) => completion({}));
    await pumpScreen(tester);

    expect(find.textContaining('Welcome'), findsOneWidget);
  });

  testWidgets('web search toggle is off by default and can be enabled', (
    tester,
  ) async {
    fake = FakeHttpClient((_, _) => completion({}));
    await pumpScreen(tester);

    expect(find.byIcon(Icons.language_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.language_outlined));
    await tester.pump();
    expect(find.byIcon(Icons.language), findsOneWidget);
  });

  testWidgets('with search on, the model searches and the answer is shown', (
    tester,
  ) async {
    fake = FakeHttpClient((path, body) {
      if (path.endsWith('/tools/search')) {
        return {
          'results': [
            {
              'title': 'Result',
              'url': 'https://example.com',
              'content': 'It is sunny.',
            },
          ],
        };
      }
      final roles = (body['messages'] as List).map((m) => m['role']).toList();
      if (!roles.contains('tool')) {
        return completion({
          'role': 'assistant',
          'content': null,
          'tool_calls': [
            {
              'id': 'c1',
              'type': 'function',
              'function': {
                'name': 'web_search',
                'arguments': '{"query":"weather"}',
              },
            },
          ],
        });
      }
      return completion({
        'role': 'assistant',
        'content': 'It is **sunny** today.',
      });
    });
    await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.language_outlined));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'weather?');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('weather?'), findsOneWidget);
    // Markdown is rendered: the ** markers are gone, the text is bold.
    expect(find.textContaining('**', findRichText: true), findsNothing);
    expect(find.textContaining('sunny', findRichText: true), findsOneWidget);
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(fake.requests.map((r) => r.$1), [
      '/chat/completions',
      '/v1/tools/search',
      '/chat/completions',
    ]);
    // The tool-call and tool-result messages stay out of the chat view.
    expect(find.textContaining('results'), findsNothing);
  });
}
