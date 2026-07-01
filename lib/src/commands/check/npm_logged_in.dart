// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_lang/gg_lang.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_process/gg_process.dart';
import 'package:gg_publish/gg_publish.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:mocktail/mocktail.dart' as mocktail;

// #############################################################################

/// Checks that the user is authenticated with the npm registry before a
/// TypeScript package is published to npm.
///
/// Without this check a missing or expired token surfaces only as a cryptic
/// `404 Not Found` in the middle of `pnpm publish` (npm masks an unauthorized
/// publish of a scoped package as a 404). Running `<pm> whoami` up front turns
/// that into an actionable "not logged in to npm" error before anything is
/// built or versioned.
///
/// The check only applies to packages whose publish target is `npm` (see
/// [PublishTo]). Dart/Flutter (`pub.dev`) and private (`none`) packages are
/// skipped.
class NpmLoggedIn extends DirCommand<void> {
  /// Constructor.
  NpmLoggedIn({
    required super.ggLog,
    this.processWrapper = const GgProcessWrapper(),
    PublishTo? publishTo,
  }) : _publishTo = publishTo ?? PublishTo(ggLog: ggLog),
       super(
         name: 'npm-logged-in',
         description:
             'Checks that the user is authenticated with the npm registry.',
       );

  /// Example instance for tests — logs to `print`.
  factory NpmLoggedIn.example() => NpmLoggedIn(ggLog: print);

  /// The process wrapper used to execute shell processes.
  final GgProcessWrapper processWrapper;

  // ...........................................................................
  @override
  Future<void> get({required Directory directory, required GgLog ggLog}) async {
    await check(directory: directory);

    // Only npm-published packages need npm authentication. `pub.dev` (Dart)
    // and `none` (private) targets are unaffected.
    final target = await _publishTo.fromDirectory(directory);
    if (target != 'npm') {
      GgStatusPrinter<void>(
        ggLog: ggLog,
        message: 'Skipping npm auth check ($target target)',
      ).logStatus(GgStatusPrinterStatus.success);
      return;
    }

    final statusPrinter = GgStatusPrinter<void>(
      ggLog: ggLog,
      message: 'Logged in to npm',
    );
    statusPrinter.logStatus(GgStatusPrinterStatus.running);

    final pm = detectTypeScriptPackageManager(directory);
    // npm/pnpm/yarn are shell shims (pnpm.cmd on Windows, a PATH script on
    // Linux/macOS), so run through a shell — otherwise Windows cannot find the
    // executable and Process.run throws "cannot find the file".
    final result = await processWrapper.run(
      pm.executable,
      const <String>['whoami'],
      workingDirectory: directory.path,
      runInShell: true,
    );

    if (result.exitCode == 0) {
      statusPrinter.logStatus(GgStatusPrinterStatus.success);
      return;
    }

    statusPrinter.logStatus(GgStatusPrinterStatus.error);
    // `whoami` reports auth failures on stderr, but fall back to stdout so the
    // cause is never swallowed.
    final err = result.stderr.toString().trim();
    final out = result.stdout.toString().trim();
    final detail = err.isNotEmpty ? err : out;
    throw Exception(
      'Not logged in to the npm registry '
      '(${pm.executable} whoami failed: $detail). '
      'Run "${pm.executable} login" or set a valid _authToken in ~/.npmrc '
      'before publishing.',
    );
  }

  // ######################
  // Private
  // ######################

  final PublishTo _publishTo;
}

// .............................................................................
/// A mocktail mock.
class MockNpmLoggedIn extends mocktail.Mock implements NpmLoggedIn {}
