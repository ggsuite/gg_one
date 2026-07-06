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
    gg_merge.WaitForMerge? waitForMerge,
    gg_publish.MainBranch? mainBranch,
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
  }) : _state = state ?? GgState(ggLog: ggLog),
       _doMerge = doMerge ?? gg_merge.DoMerge(ggLog: ggLog),
       _waitForMerge = waitForMerge ?? gg_merge.WaitForMerge(ggLog: ggLog),
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
    argParser.addFlag(
      'via-pull-request',
      help:
          'Merge through an auto-complete pull request and wait until it is '
          'merged (for protected branches, e.g. Azure DevOps).',
      negatable: true,
      defaultsTo: false,
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
  final gg_merge.WaitForMerge _waitForMerge;
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
    bool? viaPullRequest,
  }) => get(
    directory: directory,
    ggLog: ggLog,
    automerge: automerge,
    local: local,
    message: message,
    verbose: verbose,
    viaPullRequest: viaPullRequest,
  );

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    bool? automerge,
    bool? local,
    String? message,
    bool? verbose,
    bool? viaPullRequest,
  }) async {
    automerge ??= argResults?['automerge'] as bool? ?? false;
    local ??= argResults?['local'] as bool? ?? false;
    message ??= argResults?['message'] as String?;
    verbose ??= argResults?['verbose'] as bool? ?? false;
    viaPullRequest ??= argResults?['via-pull-request'] as bool? ?? false;

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

    if (viaPullRequest) {
      // Protected branches (e.g. Azure DevOps) reject a direct push to main;
      // merge through an auto-complete pull request and wait for it instead.
      await _mergeViaPullRequest(
        directory: directory,
        ggLog: ggLog,
        verbose: verbose,
      );
    } else {
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
    }

    // Save state
    await _state.writeSuccess(directory: directory, key: stateKey);

    // A merge produces a fully-committed, gg-verified HEAD, so it also
    // satisfies »gg did commit«. Record that too, otherwise the pre-push hook
    // (which runs »gg did commit«) rejects the merge commit when it is pushed.
    await _state.writeSuccess(directory: directory, key: 'doCommit');
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

  /// Merges the feature branch through an auto-complete pull request and blocks
  /// until the provider merged it. Used for protected main branches (e.g. Azure
  /// DevOps `TF402455`) where a direct push to main is rejected. Afterwards the
  /// local main branch is updated to the merged state so a version tag can be
  /// placed on it.
  Future<void> _mergeViaPullRequest({
    required Directory directory,
    required GgLog ggLog,
    required bool verbose,
  }) async {
    // Refresh remote-tracking refs so the merge pre-conditions are accurate.
    await _fetchAndPullMain(
      directory: directory,
      ggLog: ggLog,
      verbose: verbose,
    );

    // Push the feature branch (incl. version bump + changelog) so the pull
    // request contains everything before it is created.
    await _runGitCommand(
      directory: directory,
      arguments: const ['push'],
      actionDescription: 'push feature branch before creating the pull request',
      ggLog: ggLog,
      verbose: verbose,
    );

    // Create the auto-complete pull request on the provider (GitHub/Azure).
    await _doMerge.get(
      directory: directory,
      ggLog: ggLog,
      automerge: true,
      local: false,
      verbose: verbose,
    );

    // Block until the provider merged the pull request.
    await _waitForMerge.get(directory: directory, ggLog: ggLog);

    // Bring local main to the merged state so the version tag lands on it.
    final mainBranchName = await _mainBranch.get(
      directory: directory,
      ggLog: <String>[].add,
    );
    await _runGitCommand(
      directory: directory,
      arguments: ['checkout', mainBranchName],
      actionDescription: 'checkout $mainBranchName',
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
