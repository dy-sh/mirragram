# Mirragram

An unofficial Telegram client that looks and works like the official apps and
adds end-to-end encryption to regular cloud chats — private chats and groups.

Messages are encrypted on your device and sent through Telegram as text.
Telegram stores only ciphertext; people using other clients see `🔒` followed
by random characters. Both sides need this client to read each other.

> **Status: early development.** The encryption protocol is custom and has not
> been audited. Do not rely on it for anything sensitive yet.

Built with Flutter, [TDLib](https://github.com/tdlib/td) and
[libsodium](https://libsodium.org). Runs on Android, iOS, Windows, macOS and
Linux.

## How it compares

|  | Regular Telegram chat | Telegram secret chat | This client |
|---|---|---|---|
| End-to-end encryption | ❌ Telegram can read messages | ✅ | ✅ |
| Where it works | any chat | a separate new chat, empty history | inside an existing chat, with its history |
| Groups | ✅ not end-to-end | ❌ one-on-one only | ✅ |
| Sender authenticity in groups | trust in Telegram servers | — | ✅ each message signed by the sender |
| Saved Messages | ✅ not end-to-end | ❌ | ✅ |
| Platforms | all official apps | mobile apps and macOS only; not Telegram Desktop or Web | Android, iOS, Windows, macOS, Linux |
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
- **Private chats.** XChaCha20-Poly1305 with a pairwise key from X25519,
  bound to the sender and recipient, so a message can't be replayed by
  someone else or in another chat. Your own sent messages stay readable on
  all your devices.
- **Groups.** A random group key, wrapped for every member with a known key,
  up to 36 members per message. The key id is derived from the key itself.
  Group messages are signed by the sender and bound to the chat id.
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

## Download

Builds for every platform are on the
[Releases](https://github.com/dy-sh/mirragram/releases) page. They are not
signed with store certificates, so the system will warn you on first launch:

- **Android** — `mirragram-android.apk`. Allow installing apps from your
  browser or file manager when asked.
- **Windows** — unpack `mirragram-windows-x64.zip` and run `mirragram.exe`.
  If SmartScreen appears, choose *More info* → *Run anyway*.
- **macOS** (Apple Silicon) — unpack `mirragram-macos-arm64.zip`, try to open
  the app once, then allow it in *System Settings* → *Privacy & Security* →
  *Open Anyway*.
- **Linux** (x64) — unpack `mirragram-linux-x64.tar.gz` and run `mirragram`.
  Needs `libmpv` and `libsecret` (on Debian and Ubuntu: `sudo apt install
  libmpv2 libsecret-1-0`; `libmpv1` on older releases).
- **iOS** — `mirragram-ios-unsigned.ipa` has to be signed before installing,
  for example with [AltStore](https://altstore.io) or
  [SideStore](https://sidestore.io) and a free Apple ID.

## Building

Requires Flutter 3.41+ and the `api_id` and `api_hash` of your app from
https://my.telegram.org.

1. Build TDLib once for the target platform (15–60 minutes):

   | Platform | Command | Needs |
   |---|---|---|
   | Android | `./scripts/build_tdlib_android.sh` | Android SDK with NDK 28.2, cmake, ninja, gperf, perl, php, JDK |
   | iOS | `./scripts/build_tdlib_apple.sh ios` | Xcode, `brew install cmake gperf` |
   | macOS | `./scripts/build_tdlib_apple.sh macos` | Xcode, `brew install cmake gperf` |
   | Linux | `./scripts/build_tdlib_linux.sh` | `apt install cmake gperf g++ libssl-dev zlib1g-dev` |
   | Windows | `./scripts/build_tdlib_windows.ps1` | Visual Studio with C++, CMake, vcpkg |

   The library is placed in `.tdlib/out/` and bundled automatically.
   Linux builds also need `libgtk-3-dev`, `libmpv-dev` and `libsecret-1-dev`.

2. Run:
   ```sh
   flutter run --dart-define=TG_API_ID=... --dart-define=TG_API_HASH=...
   ```

Add `--dart-define=TG_DEMO=true` to try the UI with fake chats, without an
account or TDLib credentials.

Tests: `flutter test`. Repository checks: `python3 scripts/check_rules.py --all`
(`--install-hooks` runs them before every commit).

Release builds for all platforms are made by
[GitHub Actions](.github/workflows/build.yml) when a `v*` tag is pushed.

## Credits

- [TDLib](https://github.com/tdlib/td) — Boost Software License 1.0, with
  [OpenSSL](https://www.openssl.org) (Apache License 2.0) and
  [zlib](https://zlib.net) (zlib License).
- [libsodium](https://libsodium.org) via the
  [sodium](https://pub.dev/packages/sodium) package — ISC License.
- [media_kit](https://github.com/media-kit/media-kit) for video playback, built on [mpv](https://mpv.io) and
  [FFmpeg](https://ffmpeg.org).
- Passphrase word list: [EFF Large Wordlist](https://www.eff.org/dice) by the
  Electronic Frontier Foundation, licensed under
  [CC BY 3.0 US](https://creativecommons.org/licenses/by/3.0/us/).

## License

GPL-3.0. See [LICENSE](LICENSE).
