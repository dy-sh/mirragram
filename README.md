# TelClient

An unofficial Telegram client that looks and works like the official apps and
adds end-to-end encryption to regular cloud chats — private chats and groups.

Messages are encrypted on your device and sent through Telegram as text.
Telegram stores only ciphertext; people using other clients see `🔒` followed
by random characters. Both sides need this client to read each other.

> **Status: early development.** The encryption protocol is custom and has not
> been audited. Do not rely on it for anything sensitive yet.

Built with Flutter, [TDLib](https://github.com/tdlib/td) and
[libsodium](https://libsodium.org). Targets iOS and Android first, then
Windows, Linux and macOS.

## How it compares

|  | Regular Telegram chat | Telegram secret chat | This client |
|---|---|---|---|
| End-to-end encryption | ❌ Telegram can read messages | ✅ | ✅ |
| Groups | ✅ not end-to-end | ❌ one-on-one only | ✅ |
| Multiple devices | ✅ | ❌ tied to the device it was started on | ✅ the same password gives the same keys |
| History on a new device | ✅ | ❌ | ✅ |
| Forward secrecy | — | ✅ re-keyed every 100 messages or weekly | ❌ keys are long-lived |
| Where messages are stored | Telegram servers, readable by Telegram | on devices; servers keep them only until delivery | Telegram servers, as ciphertext, indefinitely |
| What a leak exposes | everything, to whoever gets into the account | the chats on that device | the whole history, to whoever learns the password |
| Offline password guessing | — | not possible, keys are random | possible against stored ciphertext; slowed by Argon2id, a generated 6-word passphrase is the default |
| Metadata (who, when, how much) | visible to Telegram | visible to Telegram | visible to Telegram |
| Media and files | ✅ | ✅ | photos and videos, not encrypted yet; other files are planned |
| Message length | 4096 characters | 4096 characters | ≈3 KB of text (≈3,000 Latin or ≈1,500 Cyrillic characters) |
| Search | ✅ on the server | on the device only | ❌ local search is planned |
| Auto-delete timer | ✅ | ✅ | ❌ not yet |
| Screenshot alerts | ❌ | ✅ | ❌ |
| Key verification | — | ✅ key fingerprint | ✅ 60-digit safety number |
| Review | — | MTProto 2.0, open-source official apps, years of public analysis | custom protocol on libsodium primitives, no audit |
| Who can read it | any Telegram app | official Telegram apps | only this client, on both sides |

This table will be updated as the client develops.

## How the encryption works

- **Keys from a password.** `Argon2id(password, salt = BLAKE2b(user id))`
  (3 passes, 256 MB) produces a seed, from which X25519 (encryption), Ed25519
  (signing) and a local storage key are derived. The password is never stored.
- **Key announcement.** Turning encryption on in a chat posts your public keys,
  signed with Ed25519. A key is accepted only if the signed user id matches the
  Telegram sender.
- **Private chats.** XChaCha20-Poly1305 with a pairwise key from X25519. Your
  own sent messages stay readable on all your devices.
- **Groups.** A random group key, wrapped for every member with a known key,
  up to 36 members per message. Group messages are signed by the sender and
  bound to the chat id.
- **Safety number.** 60 digits derived from both keys, to compare out of band.

## Features

- Telegram-like UI with two layouts: Telegram for iPhone on narrow windows,
  Telegram Desktop on wide ones.
- Themes: Day Classic, Day, Night and Night Blue, with automatic night mode.
- Chat wallpapers from your Telegram account (gradients, patterns, images) and
  built-in colors.
- Photos: viewing, a full-screen viewer, sending single photos and albums
  with a caption.
- Videos, GIFs and video messages: GIFs and video messages play silently in
  the chat, videos open in a full-screen player.
- English and Russian; the system language is used by default.

## Building

Requires Flutter 3.41+. Only macOS builds are set up so far.

1. Get `api_id` and `api_hash` at https://my.telegram.org.
2. Build TDLib (once, ~15 minutes):
   ```sh
   brew install cmake gperf openssl@3
   ./scripts/build_tdlib_macos.sh
   ```
3. Run:
   ```sh
   flutter run -d macos --dart-define=TG_API_ID=... --dart-define=TG_API_HASH=...
   ```

Add `--dart-define=TG_DEMO=true` to try the UI with fake chats, without an
account or TDLib credentials.

Tests: `flutter test`. Repository checks: `python3 scripts/check_rules.py --all`
(`--install-hooks` runs them before every commit).
