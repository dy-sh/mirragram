import 'dart:async';

import 'package:flutter/cupertino.dart';

import 'e2e/e2e_service.dart';
import 'l10n/l10n.dart';
import 'telegram/telegram_service.dart';
import 'ui/screens/auth_screen.dart';
import 'ui/screens/e2e_password_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/tg_theme.dart';
import 'ui/theme/appearance.dart';

/// Demo mode with fake chats, for working on the UI without an account:
///   flutter run -d macos --dart-define=TG_DEMO=true
const demoMode = bool.fromEnvironment('TG_DEMO');

class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.tg,
    required this.e2e,
    required this.appearance,
    required super.child,
  });

  final TelegramService tg;
  final E2eService e2e;
  final AppearanceController appearance;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}

class TelApp extends StatelessWidget {
  const TelApp({
    super.key,
    required this.tg,
    required this.e2e,
    required this.appearance,
  });

  final TelegramService tg;
  final E2eService e2e;
  final AppearanceController appearance;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      tg: tg,
      e2e: e2e,
      appearance: appearance,
      child: ListenableBuilder(
        listenable: appearance,
        builder: (context, _) => CupertinoApp(
          debugShowCheckedModeBanner: false,
          title: 'Veilgram',
          locale: appearance.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) {
            final colors = appearance.colors(
              MediaQuery.platformBrightnessOf(context),
            );
            return TgColorsScope(
              colors: colors,
              child: DefaultTextStyle(
                style: colors.cupertino.textTheme.textStyle,
                child: ColoredBox(color: colors.background, child: child),
              ),
            );
          },
          home: const _RootGate(),
        ),
      ),
    );
  }
}

class _RootGate extends StatefulWidget {
  const _RootGate();

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  bool _e2eSkipped = demoMode;
  int? _e2eInitFor;
  AppScope? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scope != null) return;
    _scope = AppScope.of(context)..tg.addListener(_onTelegram);
    _onTelegram();
  }

  @override
  void dispose() {
    _scope?.tg.removeListener(_onTelegram);
    super.dispose();
  }

  /// Loads the encryption keys of the account that is logged in.
  void _onTelegram() {
    final tg = _scope!.tg;
    final userId = tg.authStateType == 'authorizationStateReady'
        ? tg.myUserId
        : null;
    if (userId == _e2eInitFor) return;
    _e2eInitFor = userId;
    _e2eSkipped = demoMode;
    if (userId != null) unawaited(_scope!.e2e.init(userId));
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.tg, scope.e2e]),
      builder: (context, _) {
        final tg = scope.tg;
        switch (tg.authStateType) {
          case 'authorizationStateWaitPhoneNumber' ||
              'authorizationStateWaitCode' ||
              'authorizationStateWaitPassword' ||
              'authorizationStateWaitRegistration' ||
              'authorizationStateWaitOtherDeviceConfirmation' ||
              'authorizationStateWaitEmailAddress' ||
              'authorizationStateWaitEmailCode':
            return const AuthScreen();
          case 'authorizationStateReady' when tg.myUserId != null:
            if (scope.e2e.status == E2eStatus.needsPassword && !_e2eSkipped) {
              return E2ePasswordScreen(
                onSkip: () => setState(() => _e2eSkipped = true),
              );
            }
            return const HomeScreen();
          default:
            return const CupertinoPageScaffold(
              child: Center(child: CupertinoActivityIndicator()),
            );
        }
      },
    );
  }
}
