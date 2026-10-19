# DeepSeek Function Calling Example

A Flutter app that shows what **function calling** makes possible. You chat with
a DeepSeek model, and it can decide on its own to search the web or read and add
events in your Google Calendar, then answer using the results.

- **Web search**: the model calls `web_search`, backed by DeepSeek's Search API.
- **Google Calendar**: the model reads your schedule and proposes events. Nothing
  is written until you tap **Add** in a confirmation dialog.
- **Streaming chat** with Markdown rendering and tappable links.
- Every tool is opt-in, with a toggle next to the input field.

> This is a demo. See [Security notes](#security-notes) before using it with a
> real API key.

## How it works

Function calling means the model never runs anything itself. It asks your app to.

```
you ──▶ app ──▶ DeepSeek   "what do I have tomorrow?"  + the list of tools
                   │
                   ▼  the model answers with a tool call, not text:
                      list_calendar_events(start, end)
        app runs the tool (Google Calendar API)
        app ──▶ DeepSeek   the tool result
                   │
                   ▼  the model writes the final answer
you ◀── app
```

The loop lives in the [`flutter_deepseek`](https://github.com/oseeshogun/flutter_deepseek)
package (`chatWithTools`). It is bounded, because some tools are billed:

| Limit | Default | Meaning |
|---|---|---|
| `maxRounds` | 3 | Requests that may offer tools. A last request without tools forces an answer. |
| `maxToolCalls` | 6 | Total tool executions. Extra calls get an error instead of running. |

The app supplies the tools (`lib/features/calendar/`). Add your own by
implementing `ToolExecutor` and passing it to `CompositeToolExecutor`.

## Requirements

- Flutter (stable). Developed with 3.47.
- A [DeepSeek API key](https://platform.deepseek.com).
- For the calendar: a Google Cloud project (see below) and an Android device or
  emulator with Google Play Services. iOS is not configured.

## Getting started

```bash
# 1. Clone the repository
git clone https://github.com/oseeshogun/deepseek_function_call_example.git
cd deepseek_function_call_example

# 2. Install dependencies
flutter pub get

# 3. Generate the dependency-injection code (not committed)
dart run build_runner build --delete-conflicting-outputs

# 4. Add your keys
cp env.example.json env.json      # then edit env.json

# 5. Run
flutter run --dart-define-from-file=env.json
```

`flutter_deepseek` is fetched from GitHub (`main` branch) by `flutter pub get`.
To work on the package at the same time, clone it next to this repository and
temporarily use `path: ../flutter_deepseek` in `pubspec.yaml`.

### Configuration (`env.json`)

| Key | Required | Description |
|---|---|---|
| `apiKey` | yes | Your DeepSeek API key. |
| `googleServerClientId` | for the calendar | OAuth **Web** client ID from Google Cloud. |

`env.json` is git-ignored. Never commit it.

### Google Calendar setup

Google Sign-In needs a Google Cloud project. This takes about ten minutes.

1. In the [Google Cloud console](https://console.cloud.google.com), create a
   project and enable the **Google Calendar API**.
2. **Google Auth Platform → Audience**: choose **External**, keep the status on
   **Testing**, and add your Google account under **Test users**.
3. **Data Access**: add the scope `https://www.googleapis.com/auth/calendar.events`.
4. **Clients**: create an **Android** client with the package name
   `com.example.deepseek_function_call_example` and your debug certificate's SHA-1.
   Get it with:
   ```bash
   cd android && ./gradlew signingReport
   ```
5. Create a second client of type **Web application** and put its ID in
   `env.json` as `googleServerClientId`.

While the app is in *Testing*, Google expires the authorization after 7 days, and
you will need to link the account again.

## Project structure

```
lib/
  core/config/          env, dependency injection (get_it + injectable)
  features/calendar/    Google auth, Calendar REST client, calendar tools
  presentation/screens/ chat screen
test/                   unit and widget tests (no network, no real keys)
```

## Tests

```bash
flutter test
dart analyze
```

Tests use fake HTTP clients, so they need no API key and make no network calls.
They cover the tool loop, the confirmation dialog, and refusing an event.

## Cost

DeepSeek Search and Fetch are billed per successful request (see the
[pricing and guide](https://api-docs.deepseek.com/guides/search)). Web search is
off by default and can be switched on per conversation. The loop limits above
cap how many calls one question can trigger.

## Security notes

- **An API key in a mobile app is not secret.** `--dart-define` embeds it in the
  binary, so anyone with the app can extract it. This is fine for a demo on your
  own device. For anything public, put a small backend between the app and
  DeepSeek.
- The calendar scope is limited to events (`calendar.events`), and every write
  needs your explicit approval in the app.
- Web pages can contain text written to manipulate a model (prompt injection).
  Tool results are marked as untrusted data, which reduces the risk but does not
  remove it. `fetch_url` is not exposed to the model by default for this reason.

To report a vulnerability, see [SECURITY.md](SECURITY.md).

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) and the
[Code of Conduct](CODE_OF_CONDUCT.md) first.

## License

[MIT](LICENSE).

This project is not affiliated with DeepSeek or Google.
