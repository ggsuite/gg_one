// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_lang/gg_lang.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_process/gg_process.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:gg_test/gg_test.dart';
import 'package:mocktail/mocktail.dart' as mocktail;

// #############################################################################

/// Runs static analysis for a specific project type.
///
/// Implementations own the entire analysis lifecycle: invoking the underlying
/// tool, rendering progress via [GgStatusPrinter], parsing error output, and
/// throwing an [Exception] with a helpful message on failure.
abstract class Analyzer {
  /// Constructor.
  const Analyzer();

  /// Runs the analyzer against [directory]. Throws on failure.
  Future<void> run({required Directory directory, required GgLog ggLog});
}

// #############################################################################

/// Runs the catalog `analyze` command on a Dart or Flutter package.
class DartAnalyzer extends Analyzer {
  /// Constructor.
  const DartAnalyzer({
    this.processWrapper = const GgProcessWrapper(),
    this.catalog,
  });

  /// The process wrapper used to execute shell processes.
  final GgProcessWrapper processWrapper;

  /// The language catalog. Defaults to the bundled gg_lang catalog when null.
  final LanguageCatalog? catalog;

  @override
  Future<void> run({required Directory directory, required GgLog ggLog}) async {
    final cat = catalog ?? await LanguageCatalog.load();
    final command = cat.spec(ProjectType.dart).command('analyze');

    final statusPrinter = GgStatusPrinter<ProcessResult>(
      ggLog: ggLog,
      message: 'Running "${command.label}"',
    );
    statusPrinter.logStatus(GgStatusPrinterStatus.running);

    final result = await processWrapper.run(
      command.exec!,
      command.args,
      workingDirectory: directory.path,
    );

    statusPrinter.logStatus(
      result.exitCode == 0
          ? GgStatusPrinterStatus.success
          : GgStatusPrinterStatus.error,
    );

    if (result.exitCode == 0) {
      return;
    }

    final files = [
      ...ErrorInfoReader().filePathes(result.stderr as String),
      ...ErrorInfoReader().filePathes(result.stdout as String),
    ];
    ggLog(yellow('There are analyzer errors:'));
    ggLog(files.map((e) => red('- $e')).join('\n'));

    throw Exception(
      'Analyze failed. Run "${blue(command.label)}" to see details.',
    );
  }
}

// #############################################################################

/// Runs TypeScript static analysis (`tsc --noEmit`).
///
/// Linting is handled by [TypeScriptFormatter] (via ESLint) rather than
/// here, because ESLint produces auto-fixable diagnostics that belong to
/// the format phase.
class TypeScriptAnalyzer extends Analyzer {
  /// Constructor.
  const TypeScriptAnalyzer({
    this.processWrapper = const GgProcessWrapper(),
    TypeScriptPackageManager Function(Directory)? packageManager,
    this.catalog,
  }) : _packageManager = packageManager;

  /// The process wrapper used to execute shell processes.
  final GgProcessWrapper processWrapper;

  /// The language catalog. Defaults to the bundled gg_lang catalog when null.
  final LanguageCatalog? catalog;

  final TypeScriptPackageManager Function(Directory)? _packageManager;

  @override
  Future<void> run({required Directory directory, required GgLog ggLog}) async {
    final cat = catalog ?? await LanguageCatalog.load();
    final command = cat.spec(ProjectType.typescript).command('analyze');

    final pm = (_packageManager ?? detectTypeScriptPackageManager).call(
      directory,
    );
    final cmd = pm.execCommand(command.tool!, command.args);

    final statusPrinter = GgStatusPrinter<ProcessResult>(
      ggLog: ggLog,
      message: 'Running "${command.label}"',
    );
    statusPrinter.logStatus(GgStatusPrinterStatus.running);

    final result = await processWrapper.run(
      cmd.executable,
      cmd.args,
      workingDirectory: directory.path,
      // Node tooling ships as `.cmd`/`.ps1` launchers on Windows, which
      // `dart:io` can only resolve via the shell.
      runInShell: command.runInShell,
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

    throw Exception(
      'TypeScript analysis failed. '
      'Run "${blue('${cmd.executable} ${cmd.args.join(' ')}')}" '
      'to see details.',
    );
  }
}

// .............................................................................
/// A mocktail mock.
class MockAnalyzer extends mocktail.Mock implements Analyzer {}
