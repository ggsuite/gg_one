// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_log/gg_log.dart';
import 'package:gg_process/gg_process.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart';

import 'gg_state.dart';

/// Makes sure `.gg/.gg-publish.json` is listed in a repository's `.gitignore`.
///
/// The runtime publish file must be invisible to git: as an untracked file it
/// would break every is-committed check in the middle of a publish, and as a
/// tracked file its progress churn would pollute the history. This helper
/// appends the entry when it is missing and — in the standalone gg_one flow —
/// commits the `.gitignore` change right away, transplanting the recorded
/// check hashes via [GgState.updateHash] so analyze/test results stay valid.
class EnsurePublishConfigIgnored {
  /// Constructor.
  EnsurePublishConfigIgnored({
    required this.ggLog,
    GgState? state,
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
  }) : _state = state ?? GgState(ggLog: ggLog),
       _processWrapper = processWrapper;

  /// The logger used for logging.
  final GgLog ggLog;

  final GgState _state;
  final GgProcessWrapper _processWrapper;

  /// The `.gitignore` entry that hides the runtime publish file from git.
  static const String entry = '.gg/.gg-publish.json';

  /// Ensures [entry] is present in `<directory>/.gitignore`. Returns true
  /// when the file was changed (or created). With [commit] the change is
  /// committed immediately (only `.gitignore` plus the hash-transplanted
  /// `.gg/.gg.json` — other working-tree changes are left alone); without it
  /// the caller's next commit is expected to pick the change up.
  Future<bool> ensure({
    required Directory directory,
    bool commit = true,
  }) async {
    final gitignore = File(join(directory.path, '.gitignore'));
    final content = gitignore.existsSync() ? gitignore.readAsStringSync() : '';
    final hasEntry = content
        .split('\n')
        .map((line) => line.trim())
        .contains(entry);
    if (hasEntry) {
      return false;
    }

    // Capture the hash before the change so recorded check results can be
    // transplanted onto the new content (same pattern as the changelog and
    // version-bump commits in »do publish«).
    final hashBefore = commit
        ? await _state.currentHash(directory: directory, ggLog: ggLog)
        : null;

    final glue = content.isEmpty || content.endsWith('\n') ? '' : '\n';
    gitignore.writeAsStringSync('$content$glue$entry\n');

    if (commit) {
      await _state.updateHash(hash: hashBefore!, directory: directory);
      await _commitGitignore(directory);
      ggLog('Added $entry to .gitignore.');
    }
    return true;
  }

  /// Commits only `.gitignore` and the hash-transplanted `.gg/.gg.json`, so
  /// unrelated working-tree changes are never swept into this commit.
  Future<void> _commitGitignore(Directory directory) async {
    final paths = <String>['.gitignore'];
    if (File(join(directory.path, '.gg', '.gg.json')).existsSync()) {
      paths.add('.gg/.gg.json');
    }

    final add = await _processWrapper.run('git', [
      'add',
      ...paths,
    ], workingDirectory: directory.path);
    if (add.exitCode != 0) {
      throw Exception('git add ${paths.join(' ')} failed: ${add.stderr}');
    }

    final result = await _processWrapper.run('git', [
      'commit',
      '-m',
      'Ignore $entry publish runtime file',
      '--',
      ...paths,
    ], workingDirectory: directory.path);
    if (result.exitCode != 0) {
      throw Exception(
        'Committing the .gitignore entry for $entry failed: ${result.stderr}',
      );
    }
  }
}

/// Mock for [EnsurePublishConfigIgnored].
class MockEnsurePublishConfigIgnored extends Mock
    implements EnsurePublishConfigIgnored {}
