import 'package:flutter/cupertino.dart';

import '../../app.dart';
import '../../tdlib/td_client.dart';
import '../tg_theme.dart';
import '../widgets/language_picker.dart';
import '../widgets/tg_button.dart';
import '../../l10n/l10n.dart';

/// Phone number → code → cloud password (2FA) → registration.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    for (final c in [_phone, _code, _password, _firstName, _lastName]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
    } on TdError catch (e) {
      if (mounted) {
        await showTgAlert(context, context.l10n.error, _humanError(e.message));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _humanError(String message) => switch (message) {
    'PHONE_NUMBER_INVALID' => context.l10n.authPhoneInvalid,
    'PHONE_CODE_INVALID' => context.l10n.authCodeInvalid,
    'PHONE_CODE_EXPIRED' => context.l10n.authCodeExpired,
    'PASSWORD_HASH_INVALID' => context.l10n.authPasswordInvalid,
    _ => message,
  };

  @override
  Widget build(BuildContext context) {
    final tg = AppScope.of(context).tg;
    final state = tg.authState;
    final l = context.l10n;

    final (title, subtitle, fields, action) = switch (state['@type']) {
      'authorizationStateWaitPhoneNumber' => (
        l.authPhoneTitle,
        l.authPhoneHint,
        [
          TgUnderlinedField(
            controller: _phone,
            placeholder: l.authPhoneNumber,
            prefix: '+',
            keyboardType: TextInputType.phone,
            autofocus: true,
          ),
        ],
        () => _run(
          () => tg.sendPhoneNumber(
            '+${_phone.text.replaceAll(RegExp(r'\D'), '')}',
          ),
        ),
      ),
      'authorizationStateWaitCode' => (
        l.authCodeTitle,
        _codeHint(state['code_info'] as TdObject),
        [
          TgUnderlinedField(
            controller: _code,
            placeholder: l.authCode,
            keyboardType: TextInputType.number,
            autofocus: true,
            textAlign: TextAlign.center,
            onSubmitted: (_) => _run(() => tg.sendCode(_code.text.trim())),
          ),
        ],
        () => _run(() => tg.sendCode(_code.text.trim())),
      ),
      'authorizationStateWaitPassword' => (
        l.authPasswordTitle,
        [
          l.authPasswordHint,
          if ((state['password_hint'] as String).isNotEmpty)
            l.authPasswordHintValue(state['password_hint'] as String),
        ].join('\n'),
        [
          TgUnderlinedField(
            controller: _password,
            placeholder: l.password,
            obscureText: true,
            autofocus: true,
            onSubmitted: (_) => _run(() => tg.sendPassword(_password.text)),
          ),
        ],
        () => _run(() => tg.sendPassword(_password.text)),
      ),
      'authorizationStateWaitRegistration' => (
        l.authNameTitle,
        l.authNameHint,
        [
          TgUnderlinedField(
            controller: _firstName,
            placeholder: l.authFirstName,
            autofocus: true,
          ),
          TgUnderlinedField(controller: _lastName, placeholder: l.authLastName),
        ],
        () => _run(
          () => tg.register(_firstName.text.trim(), _lastName.text.trim()),
        ),
      ),
      _ => (l.authUnsupportedTitle, l.authUnsupportedHint, <Widget>[], null),
    };

    final c = TgColors.of(context);
    return CupertinoPageScaffold(
      backgroundColor: c.background,
      navigationBar: CupertinoNavigationBar(
        border: null,
        backgroundColor: c.background,
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => showLanguagePicker(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(CupertinoIcons.globe, size: 20),
              const SizedBox(width: 4),
              Text(l.languageName),
            ],
          ),
        ),
      ),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: c.primaryText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: c.secondaryText,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 32),
                  ...fields,
                  const Spacer(flex: 3),
                  if (action != null)
                    TgButton(
                      label: l.continueButton,
                      loading: _loading,
                      onPressed: action,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _codeHint(TdObject codeInfo) {
    final phone = codeInfo['phone_number'] as String;
    final type = (codeInfo['type'] as TdObject)['@type'];
    return switch (type) {
      'authenticationCodeTypeTelegramMessage' => context.l10n.authCodeSentApp(
        phone,
      ),
      'authenticationCodeTypeSms' => context.l10n.authCodeSentSms(phone),
      _ => context.l10n.authCodeSent(phone),
    };
  }
}
