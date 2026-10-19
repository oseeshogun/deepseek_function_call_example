# Security Policy

## Reporting a vulnerability

Please do **not** open a public issue for security problems.

Use GitHub's private reporting: on the repository page, go to
**Security → Report a vulnerability**. Include what you found, how to reproduce
it, and its impact. You will get a reply as soon as the maintainer can.

## Scope

This is a demo app. Things worth reporting include:

- a way for a tool result (web page, calendar text) to make the model act
  without the user's approval, such as adding an event silently
- leaking of API keys, OAuth tokens or calendar data
- the app opening unsafe links or URL schemes

## Known limitations

- An API key passed with `--dart-define` is embedded in the app binary and can be
  extracted. For public use, add a backend proxy.
- Prompt injection from web content is reduced but not eliminated.

## If you committed a secret

Revoke it with the provider immediately. Removing it from git history is not
enough, because the value may already be copied or cached.
