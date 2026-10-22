import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sodium/sodium_sumo.dart';

import 'app.dart';
import 'demo/demo_client.dart';
import 'demo/demo_driver.dart';
import 'e2e/e2e_service.dart';
import 'tdlib/td_client.dart';
import 'telegram/telegram_service.dart';
import 'ui/theme/appearance.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  try {
    final sodium = await SodiumSumoInit.init();
    var dataDir = await getApplicationSupportDirectory();
    // Each profile has its own TDLib session and keys, so several accounts
    // can run side by side.
    final profile = _profileName();
    if (profile.isNotEmpty) {
      dataDir = await Directory(
        p.join(dataDir.path, 'profiles', profile),
      ).create(recursive: true);
    }
    if (demoMode) {
      dataDir = await Directory(p.join(dataDir.path, 'demo')).create();
    }
    final tg = await TelegramService.start(
      dataDir,
      createClient: demoMode ? () => DemoTdClient.create(dataDir) : null,
    );
    final e2e = E2eService(sodium, dataDir);
    final appearance = AppearanceController(tg, dataDir);

    // Pick up keys from all incoming messages, not only in open chats.
    tg.messageUpdates.listen((u) {
      if (u['@type'] != 'updateNewMessage') return;
      final message = u['message'] as TdObject;
      e2e.ingest([message]);
      final reshare = e2e.reshareGroupKey(message);
      if (reshare != null) {
        tg.sendText(
          message['chat_id'] as int,
          reshare,
          disableLinkPreview: true,
        );
      }
    });

    final Widget app = TelApp(tg: tg, e2e: e2e, appearance: appearance);
    const driver = String.fromEnvironment('TG_DEMO_DRIVER');
    runApp(
      demoMode && driver.isNotEmpty
          ? DemoDriver(directory: driver, appearance: appearance, child: app)
          : app,
    );
  } catch (e) {
    runApp(_StartupError(e.toString()));
  }
}

String _profileName() {
  const fromDefine = String.fromEnvironment('TG_PROFILE');
  final name = fromDefine.isNotEmpty
      ? fromDefine
      : Platform.environment['TG_PROFILE'] ?? '';
  return name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
}

class _StartupError extends StatelessWidget {
  const _StartupError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => CupertinoApp(
    debugShowCheckedModeBanner: false,
    home: CupertinoPageScaffold(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    ),
  );
}
