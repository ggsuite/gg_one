// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_lang/gg_lang.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:mocktail/mocktail.dart' as mocktail;

// #############################################################################

/// The npm scripts every TypeScript project must declare in its package.json.
const List<String> requiredNpmScripts = <String>['test', 'build', 'lint'];

/// The publish-lifecycle script that must run `test`. npm's modern name is
/// `prepublishOnly`; the deprecated `prepublish` is accepted as an equivalent.
/// Exactly one of these must be present (unless the package is private).
const List<String> prepublishScriptNames = <String>[
  'prepublishOnly',
  'prepublish',
];

/// The script that the `test` script itself must run, so that building always
/// happens as part of testing.
const String testMustRunScript = 'build';

/// The script that the prepublish-lifecycle script must run. It is enough for
/// `prepublishOnly` to run `test`, because `test` in turn runs
/// [testMustRunScript] (`build`).
const String prepublishMustRunScript = 'test';

/// Checks that a TypeScript project's `package.json` declares every npm
/// script gg relies on, that its `test` script runs `build`, and that its
/// `prepublishOnly` script runs `test` — forming a `prepublishOnly` → `test`
/// → `build` chain. Packages marked `"private": true` are never published and
/// are therefore exempt from the `prepublishOnly` requirement.
///
/// Dart and Flutter projects are skipped. Cross-language bridge repos are
/// checked as TypeScript (see [checkProjectType]).
class CheckPackageJsonScripts extends DirCommand<void> {
  /// Constructor.
  CheckPackageJsonScripts({required super.ggLog})
    : super(
        name: 'package-json-scripts',
        description:
            "Checks that a TypeScript project's package.json declares all "
            'npm scripts required by gg.',
      );

  /// Example instance for tests — logs to `print`.
  factory CheckPackageJsonScripts.example() =>
      CheckPackageJsonScripts(ggLog: print);

  // ...........................................................................
  @override
  Future<void> get({required Directory directory, required GgLog ggLog}) async {
    await check(directory: directory);

    final ProjectType type;
    try {
      type = checkProjectType(directory);
    } catch (_) {
      // No recognizable manifest — nothing to check here.
      return;
    }

    // Only TypeScript-treated projects (pure TypeScript repos and bridges)
    // carry a package.json with scripts.
    if (type != ProjectType.typescript) {
      return;
    }

    final statusPrinter = GgStatusPrinter<void>(
      message: 'Checking package.json scripts',
      ggLog: ggLog,
    );
    statusPrinter.logStatus(GgStatusPrinterStatus.running);

    try {
      _check(directory);
      statusPrinter.logStatus(GgStatusPrinterStatus.success);
    } catch (_) {
      statusPrinter.logStatus(GgStatusPrinterStatus.error);
      rethrow;
    }
  }

  // ######################
  // Private
  // ######################

  // ...........................................................................
  void _check(Directory directory) {
    final scripts = readNpmScripts(directory);

    final missing = requiredNpmScripts
        .where((name) => !scripts.containsKey(name))
        .toList();
    if (missing.isNotEmpty) {
      throw Exception(
        'package.json is missing required scripts: '
        '${missing.join(', ')}. A TypeScript project must declare: '
        '${requiredNpmScripts.join(', ')} and one of '
        '${prepublishScriptNames.join(' / ')}.',
      );
    }

    // The `test` script must run `build`, so that building always happens as
    // part of testing. This applies to every TypeScript project, including
    // private ones.
    final testScript = scripts['test']!;
    if (!_referencesScript(testScript, testMustRunScript)) {
      throw Exception(
        'The "test" script must run $testMustRunScript '
        '(its command is "$testScript").',
      );
    }

    // Private packages are never published (npm/pnpm refuse to publish them),
    // so they need no publish-lifecycle script.
    if (isPrivateNpmPackage(directory)) {
      return;
    }

    // One of `prepublishOnly` (preferred) / `prepublish` must be present …
    final prepublishName = prepublishScriptNames.firstWhere(
      scripts.containsKey,
      orElse: () => '',
    );
    if (prepublishName.isEmpty) {
      throw Exception(
        'package.json is missing a publish-lifecycle script. A TypeScript '
        'project must declare one of: ${prepublishScriptNames.join(' / ')} '
        '(it must run $prepublishMustRunScript), or set "private": true.',
      );
    }

    // … and it must run `test` (which in turn runs `build`).
    final prepublish = scripts[prepublishName]!;
    if (!_referencesScript(prepublish, prepublishMustRunScript)) {
      throw Exception(
        'The "$prepublishName" script must run $prepublishMustRunScript '
        '(its command is "$prepublish").',
      );
    }
  }

  // ...........................................................................
  /// Whether [command] invokes the npm script named [name], matched as a
  /// whole word so `test` does not match `latest`.
  bool _referencesScript(String command, String name) =>
      RegExp('\\b${RegExp.escape(name)}\\b').hasMatch(command);
}

// .............................................................................
/// A mocktail mock.
class MockCheckPackageJsonScripts extends mocktail.Mock
    implements CheckPackageJsonScripts {}
