// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_process/gg_process.dart';

/// Checks out the branch belonging to a ticket in the current repository.
///
/// `gg do checkout <ticket>` fetches first so a branch that only lives on the
/// remote can be checked out as a tracking branch, then switches to it.
class DoCheckout extends DirCommand<void> {
  /// Constructor
  DoCheckout({
    required super.ggLog,
    super.name = 'checkout',
    super.description = 'Check out the branch belonging to a ticket.',
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
  }) : _processWrapper = processWrapper {
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      help: 'Prints each executed command before running it.',
      defaultsTo: false,
      negatable: false,
    );
  }

  final GgProcessWrapper _processWrapper;

  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
    String? branch,
    bool? verbose,
  }) =>
      get(directory: directory, ggLog: ggLog, branch: branch, verbose: verbose);

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    String? branch,
    bool? verbose,
  }) async {
    branch ??= _branchFromArgs;
    verbose ??= argResults?['verbose'] as bool? ?? false;

    if (branch.isEmpty) {
      throw UsageException('Missing ticket/branch name.', usage);
    }

    // Fetch first so a branch that only exists on the remote can be checked
    // out as a tracking branch.
    await _runGitCommand(
      directory: directory,
      arguments: const ['fetch'],
      actionDescription: 'fetch',
      ggLog: ggLog,
      verbose: verbose,
    );

    await _runGitCommand(
      directory: directory,
      arguments: ['checkout', branch],
      actionDescription: 'checkout $branch',
      ggLog: ggLog,
      verbose: verbose,
    );

    ggLog(green('Checked out $branch.'));
  }

  String get _branchFromArgs {
    final rest = argResults?.rest ?? const <String>[];
    return rest.isEmpty ? '' : rest.first;
  }

  /// Runs a git command and throws when it fails. Returns stdout on success.
  Future<String> _runGitCommand({
    required Directory directory,
    required List<String> arguments,
    required String actionDescription,
    required GgLog ggLog,
    required bool verbose,
  }) async {
    if (verbose) {
      ggLog('\$ git ${arguments.join(' ')}');
    }
    final result = await _processWrapper.run(
      'git',
      arguments,
      runInShell: true,
      workingDirectory: directory.path,
    );

    if (result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      final stdout = result.stdout.toString().trim();
      final details = stderr.isNotEmpty ? stderr : stdout;
      throw Exception('Failed to $actionDescription: $details');
    }
    return result.stdout.toString();
  }
}

/// Mock for [DoCheckout].
class MockDoCheckout extends MockDirCommand<void> implements DoCheckout {}
