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
const List<String> requiredNpmScripts = <String>[
  'test',
  'build',
  'lint',
  'prepublish',
];

/// The scripts that the `prepublish` script itself must run.
const List<String> prepublishMustRun = <String>['test', 'build'];

/// Checks that a TypeScript project's `package.json` declares every npm
/// script gg relies on, and that `prepublish` runs `test` and `build`.
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
        '${requiredNpmScripts.join(', ')}.',
      );
    }

    // `prepublish` must run both `test` and `build`.
    final prepublish = scripts['prepublish']!;
    final missingInPrepublish = prepublishMustRun
        .where((name) => !_referencesScript(prepublish, name))
        .toList();
    if (missingInPrepublish.isNotEmpty) {
      throw Exception(
        'The "prepublish" script must run '
        '${missingInPrepublish.join(' and ')} '
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
