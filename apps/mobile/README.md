# Sakina mobile (Flutter)

Only `lib/` and `pubspec.yaml` are committed. The platform folders
(`android/`, `ios/`, `web/`) are generated, not source — run this once after
cloning:

```bash
cd apps/mobile
flutter create . --platforms=android,ios --org tj.sakina --project-name sakina
flutter pub get
```

Then, with the backend running (`pnpm infra:up && pnpm dev` at the repo root):

```bash
# Android emulator: 10.0.2.2 is the host machine
flutter run \
  --dart-define=API_URL=http://10.0.2.2:4000 \
  --dart-define=WS_URL=ws://10.0.2.2:4001/ws

# Physical device on the same wifi — use your machine's LAN IP
flutter run \
  --dart-define=API_URL=http://192.168.1.10:4000 \
  --dart-define=WS_URL=ws://192.168.1.10:4001/ws
```

While `OTP_DEV_MODE=true`, the API returns the verification code in the
response and the sign-in screen fills it in for you. No SMS provider needed.

## Layout

| Path | Role |
| --- | --- |
| `lib/src/models.dart` | Dart mirror of `packages/protocol` |
| `lib/src/local_store.dart` | SQLite — **the only thing the UI reads from** |
| `lib/src/api_client.dart` | HTTP: auth, chat list, history backfill |
| `lib/src/socket_client.dart` | The persistent socket, reconnect + backoff |
| `lib/src/chat_repository.dart` | Frames in → SQLite → UI. Owns the outbox. |
| `lib/src/l10n.dart` | Strings, tg/ru/en, plus the Tajik locale fallback |
| `lib/src/ui/` | Four screens: phone, code, chat list, chat |

## The rule

Widgets never render a network response. Frames are written to `LocalStore`
first, and the UI re-reads from there. This is what makes the app instant on a
slow link and fully usable with the radio off — and it only holds if it is
never broken, so treat any `setState` fed directly from an HTTP or socket
response as a bug.

## Not yet verified

This code has not been compiled — it was written in an environment without the
Flutter SDK. Expect to fix analyzer complaints on first `flutter run`. The
backend it talks to *is* verified end to end; see
`services/gateway/scripts/e2e-smoke.mjs`.
