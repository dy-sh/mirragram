import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// Bundles the prebuilt libtdjson from `.tdlib/out/<os>-<arch>[-simulator]/`
/// (built by the scripts in `scripts/`).
void main(List<String> args) async => await build(args, (input, output) async {
  if (!input.config.buildCodeAssets) return;

  final code = input.config.code;
  final os = code.targetOS;
  var dirName = '${os.name}-${code.targetArchitecture.name}';
  if (os == OS.iOS && code.iOS.targetSdk == IOSSdk.iPhoneSimulator) {
    dirName += '-simulator';
  }

  final linkMode = DynamicLoadingBundled();
  final fileName = os.libraryFileName('tdjson', linkMode);
  final file = input.packageRoot.resolve('.tdlib/out/$dirName/$fileName');

  // Tests don't need TDLib, so a missing library is only a warning.
  if (!File.fromUri(file).existsSync()) {
    stderr.writeln(
      'warning: TDLib not found at ${file.toFilePath()}. '
      'Build it with a script from scripts/ (see README).',
    );
    return;
  }

  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: 'tdjson',
      linkMode: linkMode,
      file: file,
    ),
  );
  output.dependencies.add(file);
});
