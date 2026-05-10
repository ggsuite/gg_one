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
  }) => get(
    directory: directory,
    ggLog: ggLog,
    automerge: automerge,
    local: local,
    message: message,
  );

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    bool? automerge,
    bool? local,
    String? message,
  }) async {
    automerge ??= argResults?['automerge'] as bool? ?? false;
    local ??= argResults?['local'] as bool? ?? false;
    message ??= argResults?['message'] as String?;

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

    // Update local main branch via fetch + pull
    await _fetchAndPullMain(directory: directory);

    // Perform merge using gg_merge
    await _doMerge.get(
      directory: directory,
      ggLog: ggLog,
      automerge: automerge,
      local: local,
      message: message,
    );

    // Save state
    await _state.writeSuccess(directory: directory, key: stateKey);
  }

  /// Fetches and pulls the main branch before performing the merge.
  Future<void> _fetchAndPullMain({required Directory directory}) async {
    final mainBranchName = await _mainBranch.get(
      directory: directory,
      ggLog: <String>[].add,
    );

    final currentBranch = await _runGitCommand(
      directory: directory,
      arguments: const ['rev-parse', '--abbrev-ref', 'HEAD'],
      actionDescription: 'determine the current branch',
    );
    final originalBranch = currentBranch.trim();
    final switchBranches = originalBranch != mainBranchName;

    if (switchBranches) {
      await _runGitCommand(
        directory: directory,
        arguments: ['checkout', mainBranchName],
        actionDescription: 'checkout $mainBranchName',
      );
    }

    try {
      await _runGitCommand(
        directory: directory,
        arguments: const ['fetch'],
        actionDescription: 'fetch on $mainBranchName',
      );
      await _runGitCommand(
        directory: directory,
        arguments: const ['pull'],
        actionDescription: 'pull on $mainBranchName',
      );
    } finally {
      if (switchBranches) {
        await _runGitCommand(
          directory: directory,
          arguments: ['checkout', originalBranch],
          actionDescription: 'checkout $originalBranch',
        );
      }
    }
  }

  /// Runs a git command and throws when it fails. Returns stdout on success.
  Future<String> _runGitCommand({
    required Directory directory,
    required List<String> arguments,
    required String actionDescription,
  }) async {
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
