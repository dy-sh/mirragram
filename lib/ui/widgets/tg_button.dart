import 'package:flutter/cupertino.dart';

import '../tg_theme.dart';

class TgButton extends StatelessWidget {
  const TgButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = TgColors.of(context);
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        color: c.accent,
        disabledColor: c.accent.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        onPressed: loading ? null : onPressed,
        child: loading
            ? const CupertinoActivityIndicator(color: Color(0xFFFFFFFF))
            : Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

class TgUnderlinedField extends StatelessWidget {
  const TgUnderlinedField({
    super.key,
    required this.controller,
    required this.placeholder,
    this.prefix,
    this.keyboardType,
    this.obscureText = false,
    this.autofocus = false,
    this.onSubmitted,
    this.textAlign = TextAlign.start,
  });

  final TextEditingController controller;
  final String placeholder;
  final String? prefix;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final c = TgColors.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.separator, width: 0.5)),
      ),
      child: CupertinoTextField(
        controller: controller,
        placeholder: placeholder,
        keyboardType: keyboardType,
        obscureText: obscureText,
        autofocus: autofocus,
        onSubmitted: onSubmitted,
        textAlign: textAlign,
        style: TextStyle(fontSize: 20, color: c.primaryText),
        placeholderStyle: TextStyle(fontSize: 20, color: c.placeholder),
        cursorColor: c.accent,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: null,
        prefix: prefix == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  prefix!,
                  style: TextStyle(fontSize: 20, color: c.primaryText),
                ),
              ),
      ),
    );
  }
}

Future<void> showTgAlert(
  BuildContext context,
  String title, [
  String? message,
]) {
  return showCupertinoDialog<void>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
