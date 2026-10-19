import 'dart:convert';

import 'package:deepseek_function_call_example/features/calendar/calendar_auth.dart';
import 'package:deepseek_function_call_example/features/calendar/calendar_tool_executor.dart';
import 'package:deepseek_function_call_example/features/calendar/google_calendar_service.dart';
import 'package:flutter_deepseek/flutter_deepseek.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _Auth extends CalendarAuth {
  _Auth({this.linked = true});
  final bool linked;

  @override
  Future<String> accessToken() async {
    if (!linked) throw const CalendarNotLinkedException();
    return 'tok';
  }
}

class _Http extends http.BaseClient {
  _Http(this.status, this.body);
  final int status;
  final Map<String, dynamic> body;
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
    );
  }
}

ToolCall call(String name, Map<String, dynamic> args) => ToolCall(
  id: 'c',
  type: 'function',
  function: FunctionCall(name: name, arguments: jsonEncode(args)),
);

void main() {
  late _Http http_;
  var confirmed = true;
  var asked = 0;

  CalendarToolExecutor executor({bool linked = true}) {
    return CalendarToolExecutor(
      GoogleCalendarService.withClient(_Auth(linked: linked), http_),
      confirm: (draft) async {
        asked++;
        return confirmed;
      },
    );
  }

  setUp(() {
    http_ = _Http(200, {'items': []});
    confirmed = true;
    asked = 0;
  });

  test('exposes a read tool and a write tool', () {
    expect(executor().tools.map((t) => t.function.name), [
      'list_calendar_events',
      'create_calendar_event',
    ]);
  });

  test('lists events with the bearer token and the requested range', () async {
    http_ = _Http(200, {
      'items': [
        {
          'summary': 'Standup',
          'start': {'dateTime': '2026-10-20T09:00:00Z'},
          'end': {'dateTime': '2026-10-20T09:15:00Z'},
        },
        {
          'summary': 'Holiday',
          'start': {'date': '2026-10-21'},
          'end': {'date': '2026-10-22'},
        },
      ],
    });

    final out = jsonDecode(
      await executor().execute(
        call('list_calendar_events', {
          'start': '2026-10-20T00:00:00Z',
          'end': '2026-10-21T00:00:00Z',
        }),
      ),
    ) as Map;

    final events = out['events'] as List;
    expect(events.map((e) => e['title']), ['Standup', 'Holiday']);
    expect(events[1]['all_day'], true);
    expect(events[1]['start'], '2026-10-21');

    final request = http_.requests.single;
    expect(request.headers['Authorization'], 'Bearer tok');
    expect(request.url.queryParameters['timeMin'], '2026-10-20T00:00:00.000Z');
    expect(request.url.queryParameters['singleEvents'], 'true');
  });

  test('rejects bad arguments without calling Google or the user', () async {
    final ex = executor();
    final bad = <Map<String, dynamic>>[
      {'title': 'x', 'start': 'soon', 'end': 'later'},
      {
        'title': '',
        'start': '2026-10-20T10:00:00Z',
        'end': '2026-10-20T11:00:00Z',
      },
      {
        'title': 'x',
        'start': '2026-10-20T11:00:00Z',
        'end': '2026-10-20T10:00:00Z',
      },
    ];
    for (final args in bad) {
      final out = jsonDecode(
        await ex.execute(call('create_calendar_event', args)),
      ) as Map;
      expect(out, contains('error'), reason: '$args');
    }
    expect(asked, 0);
    expect(http_.requests, isEmpty);
  });

  test('declined events are not written', () async {
    confirmed = false;

    final out = jsonDecode(
      await executor().execute(
        call('create_calendar_event', {
          'title': 'Lunch',
          'start': '2026-10-20T12:00:00Z',
          'end': '2026-10-20T13:00:00Z',
        }),
      ),
    ) as Map;

    expect(out['status'], 'declined');
    expect(asked, 1);
    expect(http_.requests, isEmpty);
  });

  test('approved events are posted as UTC date-times', () async {
    http_ = _Http(200, {
      'summary': 'Lunch',
      'start': {'dateTime': '2026-10-20T12:00:00Z'},
      'end': {'dateTime': '2026-10-20T13:00:00Z'},
    });

    final out = jsonDecode(
      await executor().execute(
        call('create_calendar_event', {
          'title': 'Lunch',
          'start': '2026-10-20T13:00:00+01:00',
          'end': '2026-10-20T14:00:00+01:00',
          'location': 'Cafe',
        }),
      ),
    ) as Map;

    expect(out['status'], 'created');
    final request = http_.requests.single as http.Request;
    expect(request.method, 'POST');
    final sent = jsonDecode(request.body) as Map;
    expect(sent['start'], {'dateTime': '2026-10-20T12:00:00.000Z'});
    expect(sent['location'], 'Cafe');
    expect(sent.containsKey('description'), isFalse);
  });

  test('tells the model when the account is not linked', () async {
    final out = jsonDecode(
      await executor(linked: false).execute(
        call('list_calendar_events', {
          'start': '2026-10-20T00:00:00Z',
          'end': '2026-10-21T00:00:00Z',
        }),
      ),
    ) as Map;
    expect(out['error'], contains('not linked'));
  });

  test('turns a Google API error into a tool error', () async {
    http_ = _Http(403, {
      'error': {'message': 'Insufficient Permission'},
    });

    final out = jsonDecode(
      await executor().execute(
        call('list_calendar_events', {
          'start': '2026-10-20T00:00:00Z',
          'end': '2026-10-21T00:00:00Z',
        }),
      ),
    ) as Map;
    expect(out['error'], contains('Insufficient Permission'));
  });
}
