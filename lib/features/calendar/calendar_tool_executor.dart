import 'dart:convert';

import 'package:deepseek_function_call_example/features/calendar/calendar_auth.dart';
import 'package:deepseek_function_call_example/features/calendar/google_calendar_service.dart';
import 'package:flutter_deepseek/flutter_deepseek.dart';

/// What the model wants to add, shown to the user before anything is written.
class EventDraft {
  const EventDraft({
    required this.title,
    required this.start,
    required this.end,
    this.description,
    this.location,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final String? description;
  final String? location;
}

/// Gives the model access to the user's Google Calendar.
///
/// Reading is automatic. Writing needs [confirm] to return true, so the model
/// never changes the calendar without the user's explicit approval.
class CalendarToolExecutor implements ToolExecutor {
  const CalendarToolExecutor(this.service, {required this.confirm});

  static const listEventsName = 'list_calendar_events';
  static const createEventName = 'create_calendar_event';

  final GoogleCalendarService service;

  /// Asks the user to approve [draft]. Returns true to create the event.
  final Future<bool> Function(EventDraft draft) confirm;

  static const _dateTimeHelp =
      'ISO 8601 date and time with the UTC offset, e.g. 2026-10-20T15:00:00+01:00';

  @override
  List<DeepSeekTool> get tools => const [
    DeepSeekTool(
      function: FunctionDefinition(
        name: listEventsName,
        description:
            "List the events on the user's Google Calendar between two moments. "
            'Use it to answer questions about their schedule or to check for '
            'conflicts before adding an event.',
        parameters: {
          'type': 'object',
          'properties': {
            'start': {
              'type': 'string',
              'description': 'Start of the range. $_dateTimeHelp',
            },
            'end': {
              'type': 'string',
              'description': 'End of the range. $_dateTimeHelp',
            },
          },
          'required': ['start', 'end'],
        },
      ),
    ),
    DeepSeekTool(
      function: FunctionDefinition(
        name: createEventName,
        description:
            "Add an event or meeting to the user's Google Calendar. The user is "
            'asked to approve it first, and may refuse.',
        parameters: {
          'type': 'object',
          'properties': {
            'title': {'type': 'string', 'description': 'Event title.'},
            'start': {'type': 'string', 'description': 'Start. $_dateTimeHelp'},
            'end': {
              'type': 'string',
              'description':
                  'End. $_dateTimeHelp. If the user gave no duration, use one hour.',
            },
            'description': {'type': 'string', 'description': 'Optional notes.'},
            'location': {'type': 'string', 'description': 'Optional place.'},
          },
          'required': ['title', 'start', 'end'],
        },
      ),
    ),
  ];

  @override
  Future<String> execute(ToolCall call) async {
    final Map<String, dynamic> args;
    try {
      final decoded = jsonDecode(
        call.function.arguments.isEmpty ? '{}' : call.function.arguments,
      );
      if (decoded is! Map<String, dynamic>) {
        return _error('Arguments must be a JSON object.');
      }
      args = decoded;
    } on FormatException {
      return _error('Arguments are not valid JSON.');
    }

    try {
      return switch (call.function.name) {
        listEventsName => await _list(args),
        createEventName => await _create(args),
        final name => _error('Unknown tool "$name".'),
      };
    } on CalendarNotLinkedException {
      return _error(
        'The user has not linked Google Calendar. Ask them to link it with '
        'the calendar button.',
      );
    } on CalendarApiException catch (e) {
      return _error(e.toString());
    }
  }

  Future<String> _list(Map<String, dynamic> args) async {
    final from = _dateTime(args['start']);
    final to = _dateTime(args['end']);
    if (from == null || to == null) {
      return _error('"start" and "end" must be ISO 8601 date-times.');
    }
    if (!to.isAfter(from)) return _error('"end" must be after "start".');

    final events = await service.listEvents(from: from, to: to);
    return jsonEncode({
      'events': [
        for (final e in events)
          {
            'title': e.title,
            'start': e.allDay ? _date(e.start) : _withOffset(e.start),
            'end': e.allDay ? _date(e.end) : _withOffset(e.end),
            'all_day': e.allDay,
            'location': ?e.location,
          },
      ],
    });
  }

  Future<String> _create(Map<String, dynamic> args) async {
    final title = args['title'];
    final start = _dateTime(args['start']);
    final end = _dateTime(args['end']);
    if (title is! String || title.trim().isEmpty) {
      return _error('"title" must be a non-empty string.');
    }
    if (start == null || end == null) {
      return _error('"start" and "end" must be ISO 8601 date-times.');
    }
    if (!end.isAfter(start)) return _error('"end" must be after "start".');

    final draft = EventDraft(
      title: title.trim(),
      start: start,
      end: end,
      description: args['description'] as String?,
      location: args['location'] as String?,
    );
    if (!await confirm(draft)) {
      return jsonEncode({
        'status': 'declined',
        'message': 'The user declined. Do not retry; ask what they want.',
      });
    }

    final created = await service.createEvent(
      title: draft.title,
      start: draft.start,
      end: draft.end,
      description: draft.description,
      location: draft.location,
    );
    return jsonEncode({
      'status': 'created',
      'title': created.title,
      'start': _withOffset(created.start),
      'end': _withOffset(created.end),
      'link': ?created.link,
    });
  }

  /// Parses an ISO 8601 date-time. Without an offset it means local time.
  static DateTime? _dateTime(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  static String _date(DateTime t) => t.toIso8601String().split('T').first;

  /// ISO 8601 in local time with its UTC offset, e.g. `...T15:00:00+01:00`.
  static String _withOffset(DateTime t) {
    final local = t.toLocal();
    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final base = local.toIso8601String().split('.').first;
    return '$base$sign$hours:$minutes';
  }

  static String _error(String message) => jsonEncode({'error': message});
}
