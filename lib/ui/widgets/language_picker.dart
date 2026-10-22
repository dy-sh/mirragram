import 'package:flutter/cupertino.dart';

import '../../app.dart';
import '../../l10n/l10n.dart';

String languageName(Locale locale) =>
    lookupAppLocalizations(locale).languageName;

Future<void> showLanguagePicker(BuildContext context) {
  final appearance = AppScope.of(context).appearance;
  final l = context.l10n;
  Widget option(String? code, String title) => CupertinoActionSheetAction(
    isDefaultAction: appearance.languageCode == code,
    onPressed: () {
      appearance.setLanguage(code);
      Navigator.pop(context);
    },
    child: Text(title),
  );

  return showCupertinoModalPopup<void>(
    context: context,
    builder: (context) => CupertinoActionSheet(
      title: Text(l.language),
      actions: [
        option(null, l.languageSystem),
        for (final locale in AppLocalizations.supportedLocales)
          option(locale.languageCode, languageName(locale)),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(context),
        child: Text(l.cancel),
      ),
    ),
  );
}
