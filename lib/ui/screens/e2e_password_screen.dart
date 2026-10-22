import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../tg_theme.dart';
import '../widgets/tg_button.dart';
import '../../l10n/l10n.dart';

class E2ePasswordScreen extends StatefulWidget {
  const E2ePasswordScreen({super.key, this.onSkip, this.onDone});

  final VoidCallback? onSkip;
  final VoidCallback? onDone;

  @override
  State<E2ePasswordScreen> createState() => _E2ePasswordScreenState();
}

class _E2ePasswordScreenState extends State<E2ePasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _isNew = true;
  bool _loading = false;
  String? _generated;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final phrase = await generatePassphrase();
    if (!mounted) return;
    setState(() {
      _generated = phrase;
      _password.text = phrase;
      _confirm.clear();
    });
  }

  Future<void> _submit() async {
    final password = _password.text;
    if (_isNew) {
      final problem = passwordProblem(password);
      if (problem != null) {
        return showTgAlert(
          context,
          context.l10n.weakPassword,
          switch (problem) {
            PasswordProblem.tooShort => context.l10n.passwordTooShort,
            PasswordProblem.tooSimple => context.l10n.passwordTooSimple,
          },
        );
      }
      if (password != _generated && password != _confirm.text) {
        return showTgAlert(context, context.l10n.passwordsDontMatch);
      }
    } else if (password.isEmpty) {
      return;
    }

    setState(() => _loading = true);
    try {
      await AppScope.of(context).e2e.setPassword(password);
      widget.onDone?.call();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usingGenerated = _isNew && _password.text == _generated;
    final c = TgColors.of(context);
    return CupertinoPageScaffold(
      backgroundColor: c.background,
      navigationBar: CupertinoNavigationBar(
        border: null,
        backgroundColor: c.background,
        trailing: widget.onSkip == null
            ? null
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: widget.onSkip,
                child: Text(context.l10n.later),
              ),
      ),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              children: [
                Icon(
                  CupertinoIcons.lock_shield_fill,
                  size: 72,
                  color: c.secure,
                ),
                const SizedBox(height: 16),
                Text(
                  context.l10n.encryptionPassword,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: c.primaryText,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.encryptionPasswordInfo,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: c.secondaryText,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 24),
                CupertinoSlidingSegmentedControl<bool>(
                  groupValue: _isNew,
                  onValueChanged: (v) => setState(() {
                    _isNew = v ?? true;
                    _password.text = _isNew ? (_generated ?? '') : '';
                    _confirm.clear();
                  }),
                  children: {
                    true: Text(context.l10n.newPassword),
                    false: Text(context.l10n.existingPassword),
                  },
                ),
                const SizedBox(height: 16),
                if (usingGenerated) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: c.isDark ? c.cell : c.groupedBackground,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _generated!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                        color: c.primaryText,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      CupertinoButton(
                        onPressed: _generate,
                        child: Text(context.l10n.anotherPhrase),
                      ),
                      CupertinoButton(
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: _generated!)),
                        child: Text(context.l10n.copy),
                      ),
                      CupertinoButton(
                        onPressed: () => setState(() => _password.clear()),
                        child: Text(context.l10n.ownPassword),
                      ),
                    ],
                  ),
                  Text(
                    context.l10n.writeDownPhrase,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: c.secondaryText),
                  ),
                ] else ...[
                  TgUnderlinedField(
                    controller: _password,
                    placeholder: context.l10n.password,
                    obscureText: true,
                    autofocus: true,
                  ),
                  if (_isNew)
                    TgUnderlinedField(
                      controller: _confirm,
                      placeholder: context.l10n.repeatPassword,
                      obscureText: true,
                    ),
                ],
                const SizedBox(height: 32),
                TgButton(
                  label: _isNew
                      ? context.l10n.createKeys
                      : context.l10n.restoreKeys,
                  loading: _loading,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 6 words from the EFF list (7776 words) ≈ 77 bits of entropy.
Future<String> generatePassphrase({int words = 6}) async {
  final list = (await rootBundle.loadString('assets/eff_large_wordlist.txt'))
      .split('\n')
      .where((l) => l.contains('\t'))
      .map((l) => l.split('\t')[1].trim())
      .toList();
  final rnd = Random.secure();
  return List.generate(words, (_) => list[rnd.nextInt(list.length)]).join(' ');
}

enum PasswordProblem { tooShort, tooSimple }

/// Strict on purpose: the password can be brute-forced offline.
PasswordProblem? passwordProblem(String password) {
  if (password.length < 12) return PasswordProblem.tooShort;
  final classes = [
    RegExp(r'\p{Ll}', unicode: true),
    RegExp(r'\p{Lu}', unicode: true),
    RegExp(r'\p{Nd}', unicode: true),
    RegExp(r'[^\p{L}\p{N}]', unicode: true),
  ].where((r) => r.hasMatch(password)).length;
  if (password.length < 16 && classes < 3) return PasswordProblem.tooSimple;
  return null;
}
