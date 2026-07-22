// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_one/gg_one.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_git/gg_git_test_helpers.dart';
import 'package:gg_merge/gg_merge.dart' as gg_merge;
import 'package:gg_process/gg_process.dart';
import 'package:gg_publish/gg_publish.dart' as gg_publish;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _FakeDirectory extends Fake implements Directory {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeDirectory());
  });

  late Directory d;
  final messages = <String>[];
  final ggLog = messages.add;
  late DoMerge doMerge;
  late MockGgMergeDoMerge mockGgMergeDoMerge;
  late MockGgMergeWaitForMerge mockWaitForMerge;
  late MockGgState mockGgState;
  late MockMainBranch mockMainBranch;
  late MockGgProcessWrapper mockProcessWrapper;

  void stubGitCommands({
    String mainBranchName = 'main',
    String currentBranch = 'feature/x',
  }) {
    when(
      () => mockMainBranch.get(
        directory: any(named: 'directory'),
        ggLog: any(named: 'ggLog'),
      ),
    ).thenAnswer((_) async => mainBranchName);

    when(
      () => mockProcessWrapper.run(
        'git',
        ['rev-parse', '--abbrev-ref', 'HEAD'],
        runInShell: true,
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer((_) async => ProcessResult(0, 0, '$currentBranch\n', ''));

    when(
      () => mockProcessWrapper.run(
        'git',
        ['checkout', mainBranchName],
        runInShell: true,
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

    when(
      () => mockProcessWrapper.run(
        'git',
        ['checkout', currentBranch],
        runInShell: true,
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

    when(
      () => mockProcessWrapper.run(
        'git',
        ['fetch'],
        runInShell: true,
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

    when(
      () => mockProcessWrapper.run(
        'git',
        ['pull'],
        runInShell: true,
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

    // Clean worktree by default, so no pre-merge commit is created.
    when(
      () => mockProcessWrapper.run(
        'git',
        ['status', '--porcelain', '--untracked-files=no'],
        runInShell: true,
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

    // A real release change by default, so the pull-request path runs.
    when(
      () => mockProcessWrapper.run(
        'git',
        ['diff', '--name-only', 'origin/$mainBranchName', 'HEAD'],
        runInShell: true,
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer(
      (_) async => ProcessResult(0, 0, 'lib/src/changed.dart\n', ''),
    );
  }

  setUp(() async {
    messages.clear();
    d = await Directory.systemTemp.createTemp();
    await initGit(d);
    await addAndCommitSampleFile(d);
    mockGgMergeDoMerge = MockGgMergeDoMerge();
    mockWaitForMerge = MockGgMergeWaitForMerge();
    mockGgState = MockGgState();
    mockMainBranch = MockMainBranch();
    mockProcessWrapper = MockGgProcessWrapper();
    doMerge = DoMerge(
      ggLog: ggLog,
      doMerge: mockGgMergeDoMerge,
      waitForMerge: mockWaitForMerge,
      state: mockGgState,
      mainBranch: mockMainBranch,
      processWrapper: mockProcessWrapper,
    );

    // Default: any state write succeeds (doCommit).
    when(
      () => mockGgState.writeSuccess(
        directory: any(named: 'directory'),
        key: any(named: 'key'),
      ),
    ).thenAnswer((_) async {});
  });

  tearDown(() async {
    await d.delete(recursive: true);
  });

  group('DoMerge', () {
    group('constructor', () {
      test('should initialize with defaults', () {
        final instance = DoMerge(ggLog: ggLog);
        expect(instance.name, 'merge');
        expect(instance.description, 'Performs the merge operation.');
      });

      test('should initialize with provided parameters', () {
        final instance = DoMerge(
          ggLog: ggLog,
          state: mockGgState,
          doMerge: mockGgMergeDoMerge,
          mainBranch: mockMainBranch,
          processWrapper: mockProcessWrapper,
        );
        // Verify argParser flags are added
        expect(instance.argParser.commands.isEmpty, isTrue);
      });
    });

    test('should fetch and pull main, then call gg_merge DoMerge', () async {
      stubGitCommands();

      when(
        () => mockGgMergeDoMerge.get(
          directory: d,
          ggLog: ggLog,
          automerge: false,
          local: false,
          verbose: false,
        ),
      ).thenAnswer((_) async => true);

      await doMerge.get(directory: d, ggLog: ggLog);

      verifyInOrder([
        () => mockProcessWrapper.run(
          'git',
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          runInShell: true,
          workingDirectory: d.path,
        ),
        () => mockProcessWrapper.run(
          'git',
          ['checkout', 'main'],
          runInShell: true,
          workingDirectory: d.path,
        ),
        () => mockProcessWrapper.run(
          'git',
          ['fetch'],
          runInShell: true,
          workingDirectory: d.path,
        ),
        () => mockProcessWrapper.run(
          'git',
          ['pull'],
          runInShell: true,
          workingDirectory: d.path,
        ),
        () => mockProcessWrapper.run(
          'git',
          ['checkout', 'feature/x'],
          runInShell: true,
          workingDirectory: d.path,
        ),
        () => mockGgMergeDoMerge.get(
          directory: d,
          ggLog: ggLog,
          automerge: false,
          local: false,
          verbose: false,
        ),
        () => mockGgState.writeSuccess(directory: d, key: 'doCommit'),
      ]);
    });

    test('commits pending worktree changes before merge', () async {
      stubGitCommands();

      // A formatter / gg run left tracked files dirty after the last commit.
      when(
        () => mockProcessWrapper.run(
          'git',
          ['status', '--porcelain', '--untracked-files=no'],
          runInShell: true,
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, ' M pubspec.yaml\n', ''));

      when(
        () => mockProcessWrapper.run(
          'git',
          ['add', '--update'],
          runInShell: true,
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      when(
        () => mockProcessWrapper.run(
          'git',
          [
            'commit',
            '-m',
            'Commit pending changes before merge (e.g. release formatting)',
          ],
          runInShell: true,
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      when(
        () => mockGgMergeDoMerge.get(
          directory: d,
          ggLog: ggLog,
          automerge: false,
          local: false,
          verbose: false,
        ),
      ).thenAnswer((_) async => true);

      await doMerge.get(directory: d, ggLog: ggLog);

      // Staged and committed before the branch switch.
      verifyInOrder([
        () => mockProcessWrapper.run(
          'git',
          ['status', '--porcelain', '--untracked-files=no'],
          runInShell: true,
          workingDirectory: d.path,
        ),
        () => mockProcessWrapper.run(
          'git',
          ['add', '--update'],
          runInShell: true,
          workingDirectory: d.path,
        ),
        () => mockProcessWrapper.run(
          'git',
          [
            'commit',
            '-m',
            'Commit pending changes before merge (e.g. release formatting)',
          ],
          runInShell: true,
          workingDirectory: d.path,
        ),
        () => mockProcessWrapper.run(
          'git',
          ['checkout', 'main'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ]);
      expect(
        messages,
        contains(
          yellow(
            'Committed pending worktree changes before merge '
            '(e.g. formatter output or run state).',
          ),
        ),
      );
    });

    test('should not checkout when already on main branch', () async {
      stubGitCommands(currentBranch: 'main');

      when(
        () => mockGgMergeDoMerge.get(
          directory: d,
          ggLog: ggLog,
          automerge: false,
          local: false,
          verbose: false,
        ),
      ).thenAnswer((_) async => true);

      await doMerge.get(directory: d, ggLog: ggLog);

      verifyNever(
        () => mockProcessWrapper.run(
          'git',
          ['checkout', 'main'],
          runInShell: any(named: 'runInShell'),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      );
      verify(
        () => mockProcessWrapper.run(
          'git',
          ['fetch'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).called(1);
      verify(
        () => mockProcessWrapper.run(
          'git',
          ['pull'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).called(1);
    });

    test('should restore branch when fetch fails', () async {
      stubGitCommands();

      when(
        () => mockProcessWrapper.run(
          'git',
          ['fetch'],
          runInShell: true,
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 1, '', 'fetch failed'));

      await expectLater(
        doMerge.get(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Failed to fetch on main: fetch failed'),
          ),
        ),
      );

      verify(
        () => mockProcessWrapper.run(
          'git',
          ['checkout', 'feature/x'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).called(1);
      verifyNever(
        () => mockGgMergeDoMerge.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          automerge: any(named: 'automerge'),
          local: any(named: 'local'),
          verbose: any(named: 'verbose'),
        ),
      );
    });

    test('logs each git command when verbose is true', () async {
      stubGitCommands();

      when(
        () => mockGgMergeDoMerge.get(
          directory: d,
          ggLog: ggLog,
          automerge: false,
          local: false,
          verbose: true,
        ),
      ).thenAnswer((_) async => true);

      await doMerge.get(directory: d, ggLog: ggLog, verbose: true);

      expect(
        messages,
        containsAll(<String>[
          '\$ git rev-parse --abbrev-ref HEAD',
          '\$ git checkout main',
          '\$ git fetch',
          '\$ git pull',
          '\$ git checkout feature/x',
        ]),
      );
    });

    test('removes and commits the ticket marker before merge', () async {
      // The marker as force-added by do add.
      final ggDir = Directory('${d.path}/.gg')..createSync();
      final ticketJson = File('${ggDir.path}/.ticket.json')
        ..writeAsStringSync('{"issue_id":"x"}');

      stubGitCommands();
      when(
        () => mockProcessWrapper.run(
          'git',
          ['rm', '-f', '--ignore-unmatch', '.gg/.ticket.json'],
          runInShell: true,
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => mockProcessWrapper.run(
          'git',
          ['commit', '-m', 'Remove .gg/.ticket.json before merge'],
          runInShell: true,
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => mockGgMergeDoMerge.get(
          directory: d,
          ggLog: ggLog,
          automerge: false,
          local: false,
          verbose: false,
        ),
      ).thenAnswer((_) async => true);

      await doMerge.get(directory: d, ggLog: ggLog);

      // git rm is mocked, so the command deletes the leftover file itself.
      expect(ticketJson.existsSync(), isFalse);
      verify(
        () => mockProcessWrapper.run(
          'git',
          ['rm', '-f', '--ignore-unmatch', '.gg/.ticket.json'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).called(1);
      verify(
        () => mockProcessWrapper.run(
          'git',
          ['commit', '-m', 'Remove .gg/.ticket.json before merge'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).called(1);
      expect(
        messages,
        contains(yellow('Removed .gg/.ticket.json before merge.')),
      );
    });

    test('merges via a pull request and waits for it, then updates '
        'main', () async {
      stubGitCommands();

      // Feature-branch push before creating the pull request.
      when(
        () => mockProcessWrapper.run(
          'git',
          ['push'],
          runInShell: true,
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      // Remote PR creation (auto-complete).
      when(
        () => mockGgMergeDoMerge.get(
          directory: d,
          ggLog: ggLog,
          automerge: true,
          local: false,
          verbose: false,
          deleteSourceBranch: true,
        ),
      ).thenAnswer((_) async => true);

      // Wait until merged.
      when(
        () => mockWaitForMerge.get(directory: d, ggLog: ggLog),
      ).thenAnswer((_) async => true);

      await doMerge.get(directory: d, ggLog: ggLog, viaPullRequest: true);

      verifyInOrder([
        // _fetchAndPullMain refreshes the remote-tracking refs.
        () => mockProcessWrapper.run(
          'git',
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          runInShell: true,
          workingDirectory: d.path,
        ),
        () => mockProcessWrapper.run(
          'git',
          ['checkout', 'main'],
          runInShell: true,
          workingDirectory: d.path,
        ),
        () => mockProcessWrapper.run(
          'git',
          ['fetch'],
          runInShell: true,
          workingDirectory: d.path,
        ),
        () => mockProcessWrapper.run(
          'git',
          ['pull'],
          runInShell: true,
          workingDirectory: d.path,
        ),
        () => mockProcessWrapper.run(
          'git',
          ['checkout', 'feature/x'],
          runInShell: true,
          workingDirectory: d.path,
        ),
        // Push the feature branch, then create + wait for the PR.
        () => mockProcessWrapper.run(
          'git',
          ['push'],
          runInShell: true,
          workingDirectory: d.path,
        ),
        () => mockGgMergeDoMerge.get(
          directory: d,
          ggLog: ggLog,
          automerge: true,
          local: false,
          verbose: false,
          deleteSourceBranch: true,
        ),
        () => mockWaitForMerge.get(directory: d, ggLog: ggLog),
        // Bring local main to the merged state.
        () => mockProcessWrapper.run(
          'git',
          ['checkout', 'main'],
          runInShell: true,
          workingDirectory: d.path,
        ),
        () => mockProcessWrapper.run(
          'git',
          ['pull'],
          runInShell: true,
          workingDirectory: d.path,
        ),
        () => mockGgState.writeSuccess(directory: d, key: 'doCommit'),
      ]);

      // The local merge path must not run in the pull-request flow.
      verifyNever(
        () => mockGgMergeDoMerge.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          automerge: any(named: 'automerge'),
          local: true,
          verbose: any(named: 'verbose'),
        ),
      );
    });

    test(
      'forwards deleteSourceBranch:false to the pull-request merge',
      () async {
        stubGitCommands();

        when(
          () => mockProcessWrapper.run(
            'git',
            ['push'],
            runInShell: true,
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

        when(
          () => mockGgMergeDoMerge.get(
            directory: d,
            ggLog: ggLog,
            automerge: true,
            local: false,
            verbose: false,
            deleteSourceBranch: false,
          ),
        ).thenAnswer((_) async => true);

        when(
          () => mockWaitForMerge.get(directory: d, ggLog: ggLog),
        ).thenAnswer((_) async => true);

        when(
          () => mockGgState.writeSuccess(
            directory: d,
            key: any(named: 'key'),
          ),
        ).thenAnswer((_) async {});

        await doMerge.get(
          directory: d,
          ggLog: ggLog,
          viaPullRequest: true,
          deleteSourceBranch: false,
        );

        verify(
          () => mockGgMergeDoMerge.get(
            directory: d,
            ggLog: ggLog,
            automerge: true,
            local: false,
            verbose: false,
            deleteSourceBranch: false,
          ),
        ).called(1);
      },
    );

    test(
      'skips the pull request when the release is already on main',
      () async {
        stubGitCommands();

        // Only gg bookkeeping and lock-file drift differ from origin/main —
        // the pull request of an earlier, interrupted run was already merged
        // (squash merge, so ancestry checks cannot see it).
        when(
          () => mockProcessWrapper.run(
            'git',
            ['diff', '--name-only', 'origin/main', 'HEAD'],
            runInShell: true,
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer(
          (_) async => ProcessResult(0, 0, '.gg/.gg.json\npubspec.lock\n', ''),
        );

        await doMerge.get(directory: d, ggLog: ggLog, viaPullRequest: true);

        // No push, no pull request, no waiting — straight to main.
        verifyNever(
          () => mockProcessWrapper.run(
            'git',
            ['push'],
            runInShell: any(named: 'runInShell'),
            workingDirectory: any(named: 'workingDirectory'),
          ),
        );
        verifyNever(
          () => mockGgMergeDoMerge.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            automerge: any(named: 'automerge'),
            local: any(named: 'local'),
            verbose: any(named: 'verbose'),
            deleteSourceBranch: any(named: 'deleteSourceBranch'),
            message: any(named: 'message'),
          ),
        );
        verifyNever(
          () => mockWaitForMerge.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        );

        // Local main is still brought to the merged state.
        verify(
          () => mockProcessWrapper.run(
            'git',
            ['checkout', 'main'],
            runInShell: true,
            workingDirectory: d.path,
          ),
        ).called(2); // once in _fetchAndPullMain, once for the final checkout
        expect(
          messages.any((m) => m.contains('skipping the pull request')),
          isTrue,
        );
      },
    );

    test('commits and re-pushes pre-push-hook drift before creating the '
        'pull request', () async {
      stubGitCommands();

      // The status is checked three times: before the merge (clean), after
      // the first push (a »dart run« pre-push hook rewrote pubspec.lock) and
      // as safety net after the merge wait (clean again).
      var statusCalls = 0;
      when(
        () => mockProcessWrapper.run(
          'git',
          ['status', '--porcelain', '--untracked-files=no'],
          runInShell: true,
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async {
        statusCalls++;
        return ProcessResult(
          0,
          0,
          statusCalls == 2 ? ' M pubspec.lock\n' : '',
          '',
        );
      });

      when(
        () => mockProcessWrapper.run(
          'git',
          ['add', '--update'],
          runInShell: true,
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      when(
        () => mockProcessWrapper.run(
          'git',
          [
            'commit',
            '-m',
            'Commit pending changes before merge (e.g. release formatting)',
          ],
          runInShell: true,
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      when(
        () => mockProcessWrapper.run(
          'git',
          ['push'],
          runInShell: true,
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      when(
        () => mockGgMergeDoMerge.get(
          directory: d,
          ggLog: ggLog,
          automerge: true,
          local: false,
          verbose: false,
          deleteSourceBranch: true,
        ),
      ).thenAnswer((_) async => true);

      when(
        () => mockWaitForMerge.get(directory: d, ggLog: ggLog),
      ).thenAnswer((_) async => true);

      await doMerge.get(directory: d, ggLog: ggLog, viaPullRequest: true);

      // The drift commit was created and pushed with a second push.
      verify(
        () => mockProcessWrapper.run(
          'git',
          [
            'commit',
            '-m',
            'Commit pending changes before merge (e.g. release formatting)',
          ],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).called(1);
      verify(
        () => mockProcessWrapper.run(
          'git',
          ['push'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).called(2);
      expect(statusCalls, 3);
    });

    test('forwards the merge message to the pull-request merge', () async {
      stubGitCommands();

      when(
        () => mockProcessWrapper.run(
          'git',
          ['push'],
          runInShell: true,
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      when(
        () => mockGgMergeDoMerge.get(
          directory: d,
          ggLog: ggLog,
          automerge: true,
          local: false,
          verbose: false,
          deleteSourceBranch: true,
          message: 'Release 1.2.3',
        ),
      ).thenAnswer((_) async => true);

      when(
        () => mockWaitForMerge.get(directory: d, ggLog: ggLog),
      ).thenAnswer((_) async => true);

      await doMerge.get(
        directory: d,
        ggLog: ggLog,
        viaPullRequest: true,
        message: 'Release 1.2.3',
      );

      verify(
        () => mockGgMergeDoMerge.get(
          directory: d,
          ggLog: ggLog,
          automerge: true,
          local: false,
          verbose: false,
          deleteSourceBranch: true,
          message: 'Release 1.2.3',
        ),
      ).called(1);
    });

    group('exec', () {
      test('should call get with provided parameters', () async {
        stubGitCommands();

        when(
          () => mockGgMergeDoMerge.get(
            directory: d,
            ggLog: ggLog,
            automerge: true,
            local: true,
            verbose: false,
          ),
        ).thenAnswer((_) async => true);

        await doMerge.exec(
          directory: d,
          ggLog: ggLog,
          automerge: true,
          local: true,
        );

        verify(
          () => mockGgMergeDoMerge.get(
            directory: d,
            ggLog: ggLog,
            automerge: true,
            local: true,
            verbose: false,
          ),
        ).called(1);
      });
    });
  });
}

class MockGgMergeDoMerge extends Mock implements gg_merge.DoMerge {}

class MockGgMergeWaitForMerge extends Mock implements gg_merge.WaitForMerge {}

class MockGgState extends Mock implements GgState {}

class MockMainBranch extends Mock implements gg_publish.MainBranch {}

class MockGgProcessWrapper extends Mock implements GgProcessWrapper {}
