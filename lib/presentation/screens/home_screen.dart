import 'dart:async';
import 'dart:convert';

import 'package:deepseek_function_call_example/core/config/locator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deepseek/flutter_deepseek.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _client = locator<DeepSeekClient>();
  final _controller = TextEditingController();

  /// Full conversation as sent to the API, including tool-call messages.
  final _history = <ChatMessage>[];

  StreamSubscription<void>? _subscription;
  bool _isBusy = false;
  bool _searchEnabled = false;
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

    if (_searchEnabled) {
      _chatWithSearch();
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

  /// Lets the model search the web, then shows its final answer.
  void _chatWithSearch() {
    _subscription = _client
        .chatWithTools(
          messages: List.of(_history),
          executor: WebToolExecutor(_client),
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

  String _describe(ToolCall call) {
    try {
      final args = jsonDecode(call.function.arguments) as Map<String, dynamic>;
      final query = args['query'];
      if (query is String) return 'Searching the web: $query';
    } catch (_) {}
    return 'Searching the web…';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final messages = _visibleMessages;

    return Scaffold(
      appBar: AppBar(title: const Text('AI Function Call Assistant')),
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
          if (_isBusy && _searchEnabled)
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
