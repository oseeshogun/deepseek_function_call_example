import 'dart:async';
import 'dart:convert';

import 'package:deepseek_function_call_example/features/calendar/calendar_auth.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

/// A calendar event, reduced to what the assistant needs.
class CalendarEvent {
  const CalendarEvent({
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.location,
    this.description,
    this.link,
  });

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    DateTime? parse(Object? time) {
      final map = time as Map<String, dynamic>?;
      final value = (map?['dateTime'] ?? map?['date']) as String?;
      return value == null ? null : DateTime.tryParse(value);
    }

    final start = json['start'] as Map<String, dynamic>?;
    return CalendarEvent(
      title: json['summary'] as String? ?? '(no title)',
      start: parse(json['start']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      end: parse(json['end']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      allDay: start != null && start['date'] != null,
      location: json['location'] as String?,
      description: json['description'] as String?,
      link: json['htmlLink'] as String?,
    );
  }

  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? location;
  final String? description;
  final String? link;
}

class CalendarApiException implements Exception {
  const CalendarApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'Google Calendar error $statusCode: $message';
}

/// Minimal client for the Google Calendar REST API (primary calendar).
@lazySingleton
class GoogleCalendarService {
  GoogleCalendarService(this._auth) : _http = http.Client();

  /// For tests: uses [httpClient] instead of a real connection.
  GoogleCalendarService.withClient(this._auth, this._http);

  static const _base = 'https://www.googleapis.com/calendar/v3';

  final CalendarAuth _auth;
  final http.Client _http;

  Future<List<CalendarEvent>> listEvents({
    required DateTime from,
    required DateTime to,
    int maxResults = 25,
  }) async {
    final uri = Uri.parse('$_base/calendars/primary/events').replace(
      queryParameters: {
        'timeMin': from.toUtc().toIso8601String(),
        'timeMax': to.toUtc().toIso8601String(),
        'singleEvents': 'true',
        'orderBy': 'startTime',
        'maxResults': '$maxResults',
      },
    );
    final json = await _send('GET', uri);
    final items = json['items'] as List<dynamic>? ?? [];
    return [
      for (final item in items)
        CalendarEvent.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<CalendarEvent> createEvent({
    required String title,
    required DateTime start,
    required DateTime end,
    String? description,
    String? location,
  }) async {
    final json = await _send(
      'POST',
      Uri.parse('$_base/calendars/primary/events'),
      body: {
        'summary': title,
        'start': {'dateTime': start.toUtc().toIso8601String()},
        'end': {'dateTime': end.toUtc().toIso8601String()},
        'description': ?description,
        'location': ?location,
      },
    );
    return CalendarEvent.fromJson(json);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    final token = await _auth.accessToken();
    final request = http.Request(method, uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json';
    if (body != null) request.body = jsonEncode(body);

    final response = await http.Response.fromStream(
      await _http.send(request).timeout(const Duration(seconds: 30)),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = response.body;
      try {
        message =
            ((jsonDecode(response.body) as Map)['error'] as Map)['message']
                as String;
      } catch (_) {}
      throw CalendarApiException(response.statusCode, message);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
