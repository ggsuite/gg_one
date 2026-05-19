// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_is_flutter/gg_is_flutter.dart';
import 'package:gg_one/gg_one.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_process/gg_process.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:matcher/expect.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

/// Are the last changes ready for »git commit«?
class CanCommit extends CommandCluster {
  /// Constructor
  CanCommit({
    required super.ggLog,
    Checks? checks,
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
    super.name = 'commit',
    super.description = 'Are the last changes ready for »git commit«?',
    super.shortDescription = 'Can commit?',
    super.stateKey = 'canCommit',
  }) : _processWrapper = processWrapper,
       super(commands: _checks(checks, ggLog));

  final GgProcessWrapper _processWrapper;

  // ...........................................................................
  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    bool? force,
    bool? saveState,
  }) async {
    // Ensure pubspec.lock matches pubspec.yaml before running the checks.
    await _runPubGetOffline(directory: directory, ggLog: ggLog);

    // Execute commands.
    await super.get(directory: directory, ggLog: ggLog, force: force);
  }

  // ...........................................................................
  Future<void> _runPubGetOffline({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    if (!File(p.join(directory.path, 'pubspec.yaml')).existsSync()) {
      return;
    }

    final executable = isFlutterDir(directory) ? 'flutter' : 'dart';
    const args = ['pub', 'get', '--offline'];

    await GgStatusPrinter<bool>(
      message: 'Run »$executable ${args.join(' ')}«',
      ggLog: ggLog,
    ).logTask(
      task: () async {
        final result = await _processWrapper.run(
          executable,
          args,
          workingDirectory: directory.path,
        );

        if (result.exitCode != 0) {
          throw Exception(
            '»$executable ${args.join(' ')}« failed: ${result.stderr}',
          );
        }

        return true;
      },
      success: (success) => success,
    );
  }

  // ...........................................................................
  static List<DirCommand<void>> _checks(Checks? checks, GgLog ggLog) {
    checks ??= Checks(ggLog: ggLog);

    return [checks.analyze, checks.format, checks.tests];
  }
}

// .............................................................................
/// A mocktail mock
class MockCanCommit extends MockDirCommand<void> implements CanCommit {
  /// Makes [exec] successful or not
  @override
  void mockExec({
    required void result,
    Directory? directory,
    GgLog? ggLog,
    bool? force,
    bool? saveState,
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
        force: force,
        saveState: saveState,
      ),
    ).thenAnswer((invocation) async {
      return defaultReaction(
        doThrow: doThrow,
        invocation: invocation,
        result: null,
        message: message,
      );
    });
  }

  // ...........................................................................
  /// Mocks the result of the get command
  @override
  void mockGet({
    required void result,
    Directory? directory,
    GgLog? ggLog,
    bool? force,
    bool? saveState,
    bool doThrow = false,
    String? message,
  }) {
    when(
      () => get(
        ggLog: ggLog ?? any(named: 'ggLog'),
        directory: any(
          named: 'directory',
          that: predicate<Directory>(
            (d) => directory == null || d.path == directory.path,
          ),
        ),
        saveState: saveState,
        force: force,
      ),
    ).thenAnswer((invocation) async {
      return defaultReaction(
        doThrow: doThrow,
        invocation: invocation,
        result: null,
        message: message,
      );
    });
  }
}
