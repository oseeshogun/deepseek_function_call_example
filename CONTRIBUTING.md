# Contributing

Thanks for helping. This is a small demo project, so the process is light.

## Before you start

- For anything bigger than a small fix, open an issue first so we can agree on
  the approach before you spend time on it.
- Never commit `env.json`, API keys, keystores or tokens.

## Set up

Follow [Getting started](README.md#getting-started).

## Making a change

1. Fork the repository and create a branch from `main`.
2. Make your change. Keep it focused: one topic per pull request.
3. Add or update tests. Tests use fake HTTP clients and must not need a real API
   key or network access.
4. Run the checks:
   ```bash
   dart format .
   dart run build_runner build --delete-conflicting-outputs
   dart analyze
   flutter test
   ```
5. Open a pull request and fill in the template.

## Guidelines

- Match the style of the surrounding code. Run `dart format`.
- **Tools that write or spend money need user confirmation.** A model must never
  change a user's data, or trigger billed requests without a limit, silently.
- Treat anything returned by a tool (web pages, calendar text) as untrusted data.
- Keep generated files out of git. `locator.config.dart` is generated.
- Write commit messages that say what changed and why.

## Reporting bugs and ideas

Use the issue templates. For security problems, do **not** open a public issue.
See [SECURITY.md](SECURITY.md).

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE).
