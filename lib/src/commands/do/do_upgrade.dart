// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_one/gg_one.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_process/gg_process.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:matcher/expect.dart';
import 'package:mocktail/mocktail.dart';

/// Upgrades all dependencies
class DoUpgrade extends DirCommand<void> {
  /// Constructor
  DoUpgrade({
    required super.ggLog,
    super.name = 'upgrade',
    super.description = 'Upgrades all dependencies',
    GgState? state,
    DidUpgrade? didUpgrade,
    CanUpgrade? canUpgrade,
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
    CanCommit? canCommit,
  }) : _state = state ?? GgState(ggLog: ggLog),
       _processWrapper = processWrapper,
       _didUpgrade = didUpgrade ?? DidUpgrade(ggLog: ggLog),
       _canUpgrade = canUpgrade ?? CanUpgrade(ggLog: ggLog),
       _canCommit = canCommit ?? CanCommit(ggLog: ggLog) {
    _addParam();
  }

  // ...........................................................................
  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
    bool? majorVersions,
  }) => get(directory: directory, ggLog: ggLog, majorVersions: majorVersions);

  // ...........................................................................
  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    bool? majorVersions,
  }) async {
    majorVersions ??= _majorVersionsFromArgs;

    // Use this log method to supress logs.
    void noLog(_) {} // coverage:ignore-line

    // Does directory exist?
    await check(directory: directory);

    // Is already upgraded?
    final isDone = await _didUpgrade.get(
      directory: directory,
      ggLog: noLog,
      majorVersions: majorVersions,
    );

    if (isDone) {
      ggLog(yellow('Everything is already up to date.'));
      return;
    }

    // Can upgrade?
    await _canUpgrade.exec(directory: directory, ggLog: ggLog);

    // Remember the state before the upgrade
    final hashBefore = await _state.currentHash(
      directory: directory,
      ggLog: ggLog,
    );

    // Perform the upgrade
    await _runDartPubUpgrade(
      directory: directory,
      majorVersions: majorVersions,
    );

    // Check if everything is still running after the update
    try {
      await _canCommit.exec(
        directory: directory,
        ggLog: ggLog,
        force: true, // Checks need to be done, even if if nothing has changed
      );
    }
    // When not everything is running, reset success sate
    catch (e) {
      await _state.reset(directory: directory);
      throw Exception(
        red(
          'After the update tests are not running anymore. '
          'Please run ${blue('»gg can commit«')} and try again.',
        ),
      );
    }

    // If nothing has changed, return
    final hashAfter = await _state.currentHash(
      directory: directory,
      ggLog: ggLog,
    );

    if (hashBefore == hashAfter) {
      ggLog(yellow('No changes after the upgrade.'));
      return;
    }
  }

  /// The key used to save the state of the command
  final String stateKey = 'doUpgrade';

  // ######################
  // Private
  // ######################

  // ...........................................................................
  final GgState _state;
  final GgProcessWrapper _processWrapper;
  final DidUpgrade _didUpgrade;
  final CanUpgrade _canUpgrade;
  final CanCommit _canCommit;

  // ...........................................................................
  void _addParam() {
    argParser.addFlag(
      'major-versions',
      abbr: 'm',
      help:
          'Upgrades packages to their latest resolvable versions, '
          'and updates pubspec.yaml.',
      defaultsTo: false,
      negatable: false,
    );
  }

  // ...........................................................................
  /// Runs »dart pub upgrade«
  Future<void> _runDartPubUpgrade({
    required Directory directory,
    required bool majorVersions,
  }) async {
    final args = ['pub', 'upgrade', if (majorVersions) '--major-versions'];

    await GgStatusPrinter<bool>(
      message: 'Run »dart ${args.join(' ')}«',
      ggLog: ggLog,
    ).logTask(
      task: () async {
        final result = await _processWrapper.run(
          'dart',
          args,
          workingDirectory: directory.path,
        );

        if (result.exitCode != 0) {
          throw Exception('»dart pub upgrade« failed: ${result.stderr}');
        }

        return true;
      },
      success: (success) => success,
    );
  }

  // ...........................................................................
  bool get _majorVersionsFromArgs {
    final majorVersions = argResults?['major-versions'] as bool? ?? false;
    return majorVersions;
  }
}

/// Mock for [DoUpgrade].
class MockDoUpgrade extends MockDirCommand<void> implements DoUpgrade {
  // ...........................................................................
  /// Makes [exec] successful or not
  @override
  void mockExec({
    void result,
    GgLog? ggLog,
    Directory? directory,
    bool? majorVersions,
    bool doThrow = false,
    String? message,
  }) {
    when(
      () => exec(
        directory: any(
          named: 'directory',
          that: predicate<Directory>(
            (d) => directory == null || d.path == directory.path,
          ),
        ),
        ggLog: ggLog ?? any(named: 'ggLog'),
        majorVersions: majorVersions,
      ),
    ).thenAnswer((invocation) async {
      return defaultReaction(
        doThrow: doThrow,
        message: message,
        invocation: invocation,
        result: null,
      );
    });
  }

  // ...........................................................................
  /// Makes [get] successful or not
  @override
  void mockGet({
    void result,
    GgLog? ggLog,
    Directory? directory,
    bool? majorVersions,
    bool doThrow = false,
    String? message,
  }) {
    when(
      () => get(
        directory: any(
          named: 'directory',
          that: predicate<Directory>(
            (d) => directory == null || d.path == directory.path,
          ),
        ),
        ggLog: ggLog ?? any(named: 'ggLog'),
        majorVersions: majorVersions,
      ),
    ).thenAnswer((invocation) async {
      return defaultReaction(
        doThrow: doThrow,
        message: message,
        invocation: invocation,
        result: null,
      );
    });
  }
}
