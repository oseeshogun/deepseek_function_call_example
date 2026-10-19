import 'dart:async';
import 'dart:convert';

import 'package:deepseek_function_call_example/core/config/locator.dart';
import 'package:deepseek_function_call_example/features/calendar/calendar_auth.dart';
import 'package:deepseek_function_call_example/features/calendar/calendar_tool_executor.dart';
import 'package:deepseek_function_call_example/features/calendar/google_calendar_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deepseek/flutter_deepseek.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.promptCalendarLink = true});

  /// Offers to link Google Calendar at launch when it is not linked yet.
  final bool promptCalendarLink;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _client = locator<DeepSeekClient>();
  final _calendarAuth = locator<CalendarAuth>();
  final _calendar = locator<GoogleCalendarService>();
  final _controller = TextEditingController();

  /// Full conversation as sent to the API, including tool-call messages.
  final _history = <ChatMessage>[];

  StreamSubscription<void>? _subscription;
  bool _isBusy = false;
  bool _searchEnabled = false;
  bool _calendarEnabled = false;

  /// Whether the running turn goes through the tool-calling loop.
  bool _usesTools = false;
  String? _status;
  String? _error;

  /// Messages worth showing: what the user typed and what the assistant said.
  List<ChatMessage> get _visibleMessages => _history
      .where(
        (m) =>
            (m.role == 'user' || m.role == 'assistant') &&
            (m.toolCalls == null || m.toolCalls!.isEmpty),
      )
      .toList();

  @override
  void initState() {
    super.initState();
    _restoreCalendar();
  }

  Future<void> _restoreCalendar() async {
    try {
      final linked = await _calendarAuth.restore();
      if (mounted && linked) setState(() => _calendarEnabled = true);
    } catch (_) {
      // Not linked yet, or Google sign-in is not configured: stay unlinked.
    }
    if (mounted && widget.promptCalendarLink && !_calendarAuth.isLinked) {
      await _showCalendarDialog();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _chat(String query) {
    final text = query.trim();
    if (text.isEmpty || _isBusy) return;

    _controller.clear();
    setState(() {
      _error = null;
      _status = null;
      _isBusy = true;
      _history.add(ChatMessage.user(text));
    });

    _usesTools = _searchEnabled || _calendarEnabled;
    if (_usesTools) {
      _chatWithTools();
    } else {
      _chatStreaming();
    }
  }

  /// Streams the answer token by token, without any tool.
  void _chatStreaming() {
    final history = List.of(_history);
    setState(() => _history.add(ChatMessage.assistant('')));

    _subscription = _client
        .chatStream(messages: history)
        .listen(
          (delta) {
            setState(() {
              final last = _history.removeLast();
              _history.add(ChatMessage.assistant(last.content + delta));
            });
          },
          onError: (Object error) {
            setState(() {
              _error = error.toString();
              _isBusy = false;
              if (_history.last.content.isEmpty) _history.removeLast();
            });
          },
          onDone: () {
            if (!mounted) return;
            setState(() => _isBusy = false);
          },
        );
  }

  /// Lets the model use the enabled tools, then shows its final answer.
  void _chatWithTools() {
    _subscription = _client
        .chatWithTools(
          messages: List.of(_history),
          systemPrompt: _systemPrompt(),
          executor: CompositeToolExecutor([
            if (_searchEnabled) WebToolExecutor(_client),
            if (_calendarEnabled)
              CalendarToolExecutor(_calendar, confirm: _confirmEvent),
          ]),
        )
        .listen(
          (event) {
            setState(() {
              switch (event) {
                case ToolCallRequested(:final call):
                  _status = _describe(call);
                case ToolCallCompleted():
                  _status = null;
                case ChatAnswer(:final newMessages):
                  _history.addAll(newMessages);
              }
            });
          },
          onError: (Object error) {
            setState(() {
              _error = error.toString();
              _status = null;
              _isBusy = false;
            });
          },
          onDone: () {
            if (!mounted) return;
            setState(() {
              _status = null;
              _isBusy = false;
            });
          },
        );
  }

  Future<void> _openLink(String? href) async {
    final uri = href == null ? null : Uri.tryParse(href);
    // Only web links: model output is untrusted, so no tel:, intent:, etc.
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Cannot open $href')));
    }
  }

  /// Tells the model what it cannot know: today's date and the user's zone.
  String _systemPrompt() {
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hh = offset.inHours.abs().toString().padLeft(2, '0');
    final mm = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return 'Current date and time: ${now.toIso8601String().split('.').first} '
        '(${now.timeZoneName}, UTC$sign$hh:$mm). Resolve words like "today" '
        'and "tomorrow" from it. Your knowledge has a cutoff: for recent '
        'events, dates or facts you are unsure about, search the web instead '
        'of assuming. Use the calendar tools for anything about the user\'s '
        'schedule, and never claim an event was added unless the tool '
        'returned status "created".';
  }

  String _describe(ToolCall call) {
    Map<String, dynamic> args = {};
    try {
      args = jsonDecode(call.function.arguments) as Map<String, dynamic>;
    } catch (_) {}
    switch (call.function.name) {
      case DeepSeekTools.webSearchName:
        final query = args['query'];
        return query is String
            ? 'Searching the web: $query'
            : 'Searching the web…';
      case CalendarToolExecutor.listEventsName:
        return 'Reading your calendar…';
      case CalendarToolExecutor.createEventName:
        final title = args['title'];
        return title is String
            ? 'Adding to your calendar: $title'
            : 'Adding to your calendar…';
      default:
        return 'Running ${call.function.name}…';
    }
  }

  /// Asks the user to approve an event before the model may create it.
  Future<bool> _confirmEvent(EventDraft draft) async {
    if (!mounted) return false;
    final loc = MaterialLocalizations.of(context);
    String when(DateTime t) =>
        '${loc.formatFullDate(t)}, ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(t))}';
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Add this event to Google Calendar?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(draft.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('From: ${when(draft.start.toLocal())}'),
            Text('To: ${when(draft.end.toLocal())}'),
            if (draft.location != null) Text('Where: ${draft.location}'),
            if (draft.description != null) Text(draft.description!),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Refuse'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    return approved ?? false;
  }

  /// Dialog to link or unlink the Google account.
  Future<void> _showCalendarDialog() async {
    final linked = _calendarAuth.isLinked;
    final action = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Google Calendar'),
        content: Text(
          linked
              ? 'Linked as ${_calendarAuth.email}.\n\nThe assistant can read '
                    'your events and add new ones, but only after you approve '
                    'each addition.'
              : 'Link your Google account so the assistant can read your '
                    'events and add new ones. Google will ask for your '
                    'permission, and you approve each event before it is '
                    'added.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(linked ? 'Unlink' : 'Link account'),
          ),
        ],
      ),
    );
    if (action != true || !mounted) return;

    try {
      if (linked) {
        await _calendarAuth.unlink();
      } else {
        await _calendarAuth.link();
      }
      if (mounted) setState(() => _calendarEnabled = _calendarAuth.isLinked);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Google sign-in failed: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final messages = _visibleMessages;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Function Call Assistant'),
        actions: [
          IconButton(
            tooltip: 'Google Calendar settings',
            icon: const Icon(Icons.manage_accounts_outlined),
            onPressed: _isBusy ? null : _showCalendarDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      'Welcome to the AI Function Call Assistant!',
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8.0),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isUser = message.role == 'user';
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4.0),
                          padding: const EdgeInsets.all(12.0),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width * 0.8,
                          ),
                          decoration: BoxDecoration(
                            color: isUser
                                ? theme.colorScheme.primaryContainer
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                          child: isUser || message.content.isEmpty
                              ? Text(
                                  message.content.isEmpty
                                      ? '…'
                                      : message.content,
                                )
                              : MarkdownBody(
                                  data: message.content,
                                  selectable: true,
                                  onTapLink: (text, href, title) =>
                                      _openLink(href),
                                ),
                        ),
                      );
                    },
                  ),
          ),
          if (_isBusy && _usesTools)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _status ?? 'Thinking…',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                'Error: $_error',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_isBusy,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Demande à l\'assistant',
                    ),
                    onSubmitted: _chat,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: _searchEnabled
                      ? 'Web search on (billed per request)'
                      : 'Web search off',
                  isSelected: _searchEnabled,
                  icon: const Icon(Icons.language_outlined),
                  selectedIcon: const Icon(Icons.language),
                  onPressed: _isBusy
                      ? null
                      : () => setState(() => _searchEnabled = !_searchEnabled),
                ),
                IconButton.filledTonal(
                  tooltip: !_calendarAuth.isLinked
                      ? 'Link Google Calendar'
                      : _calendarEnabled
                      ? 'Calendar on'
                      : 'Calendar off',
                  isSelected: _calendarEnabled,
                  icon: const Icon(Icons.calendar_month_outlined),
                  selectedIcon: const Icon(Icons.calendar_month),
                  onPressed: _isBusy
                      ? null
                      : () {
                          if (_calendarAuth.isLinked) {
                            setState(
                              () => _calendarEnabled = !_calendarEnabled,
                            );
                          } else {
                            _showCalendarDialog();
                          }
                        },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
