// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_one/src/tools/type_script_package_manager.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_is_github/gg_is_github.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_process/gg_process.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:gg_test/gg_test.dart';
import 'package:mocktail/mocktail.dart' as mocktail;

// #############################################################################

/// Applies formatting rules to a project's source code.
///
/// Implementations own the entire format lifecycle: invoking the underlying
/// tool, rendering progress via [GgStatusPrinter], and throwing an
/// [Exception] on failure.
abstract class Formatter {
  /// Constructor.
  const Formatter();

  /// Runs the formatter against [directory]. Throws on failure.
  Future<void> run({required Directory directory, required GgLog ggLog});
}

// #############################################################################

/// Runs `dart format` on a Dart or Flutter package.
class DartFormatter extends Formatter {
  /// Constructor.
  const DartFormatter({
    this.processWrapper = const GgProcessWrapper(),
    bool Function()? isGitHub,
  }) : _isGitHubImpl = isGitHub;

  /// The process wrapper used to execute shell processes.
  final GgProcessWrapper processWrapper;

  final bool Function()? _isGitHubImpl;
  bool get _isGitHub => _isGitHubImpl != null ? _isGitHubImpl() : isGitHub;

  @override
  Future<void> run({required Directory directory, required GgLog ggLog}) async {
    final statusPrinter = GgStatusPrinter<ProcessResult>(
      ggLog: ggLog,
      message: 'Running "dart format"',
    );
    statusPrinter.logStatus(GgStatusPrinterStatus.running);

    final result = await processWrapper.run('dart', [
      'format',
      '.',
      '-o',
      'write',
      '--set-exit-if-changed',
    ], workingDirectory: directory.path);

    if (result.exitCode == 0) {
      statusPrinter.logStatus(GgStatusPrinterStatus.success);
      return;
    }

    final std = '${result.stderr as String}\n${result.stdout as String}';
    final files = ErrorInfoReader().filePathes(std);

    // On GitHub runners, fail the build when formatting would have changed
    // files and list the culprits. Locally, `dart format` already rewrote
    // the files in-place, so the run is considered successful.
    if (_isGitHub && files.isNotEmpty) {
      statusPrinter.logStatus(GgStatusPrinterStatus.error);
      ggLog(yellow('The following files were formatted:'));
      ggLog(files.map((e) => '- ${red(e)}').join('\n'));
      throw Exception('dart format failed.');
    }

    if (files.isEmpty) {
      statusPrinter.logStatus(GgStatusPrinterStatus.error);
      ggLog(brightBlack('std'));
      throw Exception('dart format failed.');
    }

    statusPrinter.logStatus(GgStatusPrinterStatus.success);
  }
}

// #############################################################################

/// Runs ESLint to apply lint + formatting fixes to a TypeScript project.
///
/// Locally, invokes `eslint --fix` so auto-fixable issues are rewritten in
/// place. On GitHub runners, invokes `eslint` (no `--fix`) so the CI job
/// fails when sources would need to change.
class TypeScriptFormatter extends Formatter {
  /// Constructor.
  const TypeScriptFormatter({
    this.processWrapper = const GgProcessWrapper(),
    bool Function()? isGitHub,
    TypeScriptPackageManager Function(Directory)? packageManager,
  }) : _isGitHubImpl = isGitHub,
       _packageManager = packageManager;

  /// The process wrapper used to execute shell processes.
  final GgProcessWrapper processWrapper;

  final bool Function()? _isGitHubImpl;
  bool get _isGitHub => _isGitHubImpl != null ? _isGitHubImpl() : isGitHub;

  final TypeScriptPackageManager Function(Directory)? _packageManager;

  @override
  Future<void> run({required Directory directory, required GgLog ggLog}) async {
    final pm = (_packageManager ?? detectTypeScriptPackageManager).call(
      directory,
    );
    final eslintArgs = _isGitHub ? <String>[] : <String>['--fix'];
    final cmd = pm.execCommand('eslint', eslintArgs);

    final statusPrinter = GgStatusPrinter<ProcessResult>(
      ggLog: ggLog,
      message: 'Running "eslint"',
    );
    statusPrinter.logStatus(GgStatusPrinterStatus.running);

    final result = await processWrapper.run(
      cmd.executable,
      cmd.args,
      workingDirectory: directory.path,
      // Node tooling ships as `.cmd`/`.ps1` launchers on Windows, which
      // `dart:io` can only resolve via the shell.
      runInShell: true,
    );

    statusPrinter.logStatus(
      result.exitCode == 0
          ? GgStatusPrinterStatus.success
          : GgStatusPrinterStatus.error,
    );

    if (result.exitCode == 0) {
      return;
    }

    final stdout = result.stdout as String;
    final stderr = result.stderr as String;
    if (stdout.isNotEmpty) ggLog(stdout.trimRight());
    if (stderr.isNotEmpty) ggLog(stderr.trimRight());

    throw Exception('eslint failed.');
  }
}

// .............................................................................
/// A mocktail mock.
class MockFormatter extends mocktail.Mock implements Formatter {}
