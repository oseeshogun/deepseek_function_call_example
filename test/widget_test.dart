import 'dart:convert';

import 'package:deepseek_function_call_example/core/config/locator.dart';
import 'package:deepseek_function_call_example/features/calendar/calendar_auth.dart';
import 'package:deepseek_function_call_example/features/calendar/google_calendar_service.dart';
import 'package:deepseek_function_call_example/presentation/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deepseek/flutter_deepseek.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// A calendar account that is already linked, with a fixed token.
class FakeCalendarAuth extends CalendarAuth {
  FakeCalendarAuth({this.linked = true});

  final bool linked;

  @override
  bool get isLinked => linked;

  @override
  String? get email => linked ? 'me@example.com' : null;

  @override
  Future<bool> restore() async => linked;

  @override
  Future<String> accessToken() async {
    if (!linked) throw const CalendarNotLinkedException();
    return 'token';
  }
}

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

/// Pumps frames until [finder] matches. `pumpAndSettle` cannot be used while
/// the busy spinner is animating.
Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 50 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets);
}

void main() {
  late FakeHttpClient fake;

  Future<void> pumpScreen(
    WidgetTester tester, {
    bool calendarLinked = false,
    bool promptCalendarLink = false,
  }) async {
    await locator.reset();
    final auth = FakeCalendarAuth(linked: calendarLinked);
    locator.registerSingleton<CalendarAuth>(auth);
    locator.registerSingleton(GoogleCalendarService.withClient(auth, fake));
    locator.registerSingleton(DeepSeekClient(apiKey: 'k', httpClient: fake));
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(promptCalendarLink: promptCalendarLink)),
    );
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

  testWidgets('calendar: the model proposes an event, the user approves it', (
    tester,
  ) async {
    fake = FakeHttpClient((path, body) {
      if (path.endsWith('/calendars/primary/events')) {
        return {
          'summary': 'Dentist',
          'start': {'dateTime': '2026-10-20T14:00:00Z'},
          'end': {'dateTime': '2026-10-20T15:00:00Z'},
          'htmlLink': 'https://calendar.google.com/event?eid=1',
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
                'name': 'create_calendar_event',
                'arguments': jsonEncode({
                  'title': 'Dentist',
                  'start': '2026-10-20T14:00:00Z',
                  'end': '2026-10-20T15:00:00Z',
                }),
              },
            },
          ],
        });
      }
      return completion({'role': 'assistant', 'content': 'Added Dentist.'});
    });
    await pumpScreen(tester, calendarLinked: true);

    await tester.enterText(find.byType(TextField), 'dentist tomorrow 3pm');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpUntilFound(
      tester,
      find.text('Add this event to Google Calendar?'),
    );

    // Nothing is written until the user approves.
    expect(find.text('Add this event to Google Calendar?'), findsOneWidget);
    expect(find.text('Dentist'), findsOneWidget);
    expect(fake.requests.where((r) => r.$1.contains('/calendars/')), isEmpty);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.text('Added Dentist.'), findsOneWidget);
    final create = fake.requests.singleWhere(
      (r) => r.$1.contains('/calendars/'),
    );
    expect(create.$2['summary'], 'Dentist');
    // The model was told the date and zone through the system prompt.
    final first = fake.requests.first.$2['messages'] as List;
    expect(first.first['role'], 'system');
    expect(first.first['content'], contains('Current date and time'));
  });

  testWidgets('calendar: refusing the event writes nothing', (tester) async {
    fake = FakeHttpClient((path, body) {
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
                'name': 'create_calendar_event',
                'arguments': jsonEncode({
                  'title': 'Dentist',
                  'start': '2026-10-20T14:00:00Z',
                  'end': '2026-10-20T15:00:00Z',
                }),
              },
            },
          ],
        });
      }
      return completion({'role': 'assistant', 'content': 'Okay, not added.'});
    });
    await pumpScreen(tester, calendarLinked: true);

    await tester.enterText(find.byType(TextField), 'dentist');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpUntilFound(
      tester,
      find.text('Add this event to Google Calendar?'),
    );
    await tester.tap(find.text('Refuse'));
    await tester.pumpAndSettle();

    expect(find.text('Okay, not added.'), findsOneWidget);
    expect(fake.requests.where((r) => r.$1.contains('/calendars/')), isEmpty);
  });

  testWidgets('offers to link Google Calendar at launch when not linked', (
    tester,
  ) async {
    fake = FakeHttpClient((_, _) => completion({}));
    await pumpScreen(tester, promptCalendarLink: true);
    await tester.pumpAndSettle();

    expect(find.text('Google Calendar'), findsOneWidget);
    expect(find.text('Link account'), findsOneWidget);
  });

  testWidgets('does not prompt at launch when already linked', (tester) async {
    fake = FakeHttpClient((_, _) => completion({}));
    await pumpScreen(tester, calendarLinked: true, promptCalendarLink: true);
    await tester.pumpAndSettle();

    expect(find.text('Link account'), findsNothing);
  });
}
