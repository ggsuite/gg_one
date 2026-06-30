// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_one/gg_one.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_merge/gg_merge.dart' as gg_merge;
import 'package:gg_process/gg_process.dart';
import 'package:gg_publish/gg_publish.dart' as gg_publish;
import 'package:path/path.dart' as p;

/// Performs the merge operation.
class DoMerge extends DirCommand<void> {
  /// Constructor
  DoMerge({
    required super.ggLog,
    super.name = 'merge',
    super.description = 'Performs the merge operation.',
    GgState? state,
    gg_merge.DoMerge? doMerge,
    gg_publish.MainBranch? mainBranch,
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
  }) : _state = state ?? GgState(ggLog: ggLog),
       _doMerge = doMerge ?? gg_merge.DoMerge(ggLog: ggLog),
       _mainBranch = mainBranch ?? gg_publish.MainBranch(ggLog: ggLog),
       _processWrapper = processWrapper {
    argParser.addFlag(
      'automerge',
      abbr: 'a',
      help: 'Set PR/MR to automerge after CI.',
      negatable: true,
      defaultsTo: false,
    );
    argParser.addFlag(
      'local',
      abbr: 'l',
      help: 'Perform a local merge instead of remote PR/MR.',
      negatable: true,
      defaultsTo: true,
    );
    argParser.addOption(
      'message',
      abbr: 'm',
      help: 'The merge commit message.',
    );
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      help: 'Prints each executed command before running it.',
      defaultsTo: false,
      negatable: false,
    );
  }

  final GgState _state;
  final gg_merge.DoMerge _doMerge;
  final gg_publish.MainBranch _mainBranch;
  final GgProcessWrapper _processWrapper;

  /// The key used to save the state of the command
  final String stateKey = 'doMerge';

  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
    bool? automerge,
    bool? local,
    String? message,
    bool? verbose,
  }) => get(
    directory: directory,
    ggLog: ggLog,
    automerge: automerge,
    local: local,
    message: message,
    verbose: verbose,
  );

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    bool? automerge,
    bool? local,
    String? message,
    bool? verbose,
  }) async {
    automerge ??= argResults?['automerge'] as bool? ?? false;
    local ??= argResults?['local'] as bool? ?? false;
    message ??= argResults?['message'] as String?;
    verbose ??= argResults?['verbose'] as bool? ?? false;

    // Check state
    final isDone = await _state.readSuccess(
      directory: directory,
      key: stateKey,
      ggLog: ggLog,
    );

    if (isDone) {
      ggLog(yellow('Merge already performed.'));
      return;
    }

    // Drop the ticket marker (written by `gg do add`) so it never lands on
    // the main branch.
    await _removeTicketJson(
      directory: directory,
      ggLog: ggLog,
      verbose: verbose,
    );

    // Update local main branch via fetch + pull
    await _fetchAndPullMain(
      directory: directory,
      ggLog: ggLog,
      verbose: verbose,
    );

    // Perform merge using gg_merge
    await _doMerge.get(
      directory: directory,
      ggLog: ggLog,
      automerge: automerge,
      local: local,
      message: message,
      verbose: verbose,
    );

    // Save state
    await _state.writeSuccess(directory: directory, key: stateKey);
  }

  /// Removes the `.gg/.ticket.json` marker (force-added by `gg do add`) before
  /// merging and commits the removal onto the feature branch, so the marker
  /// never reaches the main branch. A no-op when the marker is absent.
  Future<void> _removeTicketJson({
    required Directory directory,
    required GgLog ggLog,
    required bool verbose,
  }) async {
    final ticketJson = File(p.join(directory.path, '.gg', '.ticket.json'));
    if (!ticketJson.existsSync()) {
      return;
    }

    await _runGitCommand(
      directory: directory,
      arguments: const ['rm', '-f', '--ignore-unmatch', '.gg/.ticket.json'],
      actionDescription: 'remove .gg/.ticket.json',
      ggLog: ggLog,
      verbose: verbose,
    );
    // `git rm` removes a tracked file; delete a still-present (untracked) copy
    // explicitly so the worktree is clean either way.
    if (ticketJson.existsSync()) {
      ticketJson.deleteSync();
    }

    await _runGitCommand(
      directory: directory,
      arguments: const ['commit', '-m', 'Remove .gg/.ticket.json before merge'],
      actionDescription: 'commit removal of .gg/.ticket.json',
      ggLog: ggLog,
      verbose: verbose,
    );
    ggLog(yellow('Removed .gg/.ticket.json before merge.'));
  }

  /// Fetches and pulls the main branch before performing the merge.
  Future<void> _fetchAndPullMain({
    required Directory directory,
    required GgLog ggLog,
    required bool verbose,
  }) async {
    final mainBranchName = await _mainBranch.get(
      directory: directory,
      ggLog: <String>[].add,
    );

    final currentBranch = await _runGitCommand(
      directory: directory,
      arguments: const ['rev-parse', '--abbrev-ref', 'HEAD'],
      actionDescription: 'determine the current branch',
      ggLog: ggLog,
      verbose: verbose,
    );
    final originalBranch = currentBranch.trim();
    final switchBranches = originalBranch != mainBranchName;

    if (switchBranches) {
      await _runGitCommand(
        directory: directory,
        arguments: ['checkout', mainBranchName],
        actionDescription: 'checkout $mainBranchName',
        ggLog: ggLog,
        verbose: verbose,
      );
    }

    try {
      await _runGitCommand(
        directory: directory,
        arguments: const ['fetch'],
        actionDescription: 'fetch on $mainBranchName',
        ggLog: ggLog,
        verbose: verbose,
      );
      await _runGitCommand(
        directory: directory,
        arguments: const ['pull'],
        actionDescription: 'pull on $mainBranchName',
        ggLog: ggLog,
        verbose: verbose,
      );
    } finally {
      if (switchBranches) {
        await _runGitCommand(
          directory: directory,
          arguments: ['checkout', originalBranch],
          actionDescription: 'checkout $originalBranch',
          ggLog: ggLog,
          verbose: verbose,
        );
      }
    }
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

/// Mock for [DoMerge].
class MockDoMerge extends MockDirCommand<void> implements DoMerge {}
