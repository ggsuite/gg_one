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
  }

  setUp(() async {
    messages.clear();
    d = await Directory.systemTemp.createTemp();
    await initGit(d);
    await addAndCommitSampleFile(d);
    mockGgMergeDoMerge = MockGgMergeDoMerge();
    mockGgState = MockGgState();
    mockMainBranch = MockMainBranch();
    mockProcessWrapper = MockGgProcessWrapper();
    doMerge = DoMerge(
      ggLog: ggLog,
      doMerge: mockGgMergeDoMerge,
      state: mockGgState,
      mainBranch: mockMainBranch,
      processWrapper: mockProcessWrapper,
    );
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
        expect(instance.stateKey, 'doMerge');
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
      when(
        () =>
            mockGgState.readSuccess(directory: d, key: 'doMerge', ggLog: ggLog),
      ).thenAnswer((_) async => false);

      stubGitCommands();

      when(
        () => mockGgMergeDoMerge.get(
          directory: d,
          ggLog: ggLog,
          automerge: false,
          local: false,
        ),
      ).thenAnswer((_) async => true);

      when(
        () => mockGgState.writeSuccess(directory: d, key: 'doMerge'),
      ).thenAnswer((_) async {});

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
        ),
        () => mockGgState.writeSuccess(directory: d, key: 'doMerge'),
      ]);
    });

    test('should not checkout when already on main branch', () async {
      when(
        () =>
            mockGgState.readSuccess(directory: d, key: 'doMerge', ggLog: ggLog),
      ).thenAnswer((_) async => false);

      stubGitCommands(currentBranch: 'main');

      when(
        () => mockGgMergeDoMerge.get(
          directory: d,
          ggLog: ggLog,
          automerge: false,
          local: false,
        ),
      ).thenAnswer((_) async => true);

      when(
        () => mockGgState.writeSuccess(directory: d, key: 'doMerge'),
      ).thenAnswer((_) async {});

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
      when(
        () =>
            mockGgState.readSuccess(directory: d, key: 'doMerge', ggLog: ggLog),
      ).thenAnswer((_) async => false);

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
        ),
      );
    });

    test('should not perform merge if already done', () async {
      when(
        () =>
            mockGgState.readSuccess(directory: d, key: 'doMerge', ggLog: ggLog),
      ).thenAnswer((_) async => true);

      await doMerge.get(directory: d, ggLog: ggLog);

      expect(messages.last, yellow('Merge already performed.'));
      verifyNever(() => mockGgMergeDoMerge.get(directory: d, ggLog: ggLog));
      verifyZeroInteractions(mockProcessWrapper);
    });

    group('exec', () {
      test('should call get with provided parameters', () async {
        when(
          () => mockGgState.readSuccess(
            directory: d,
            key: 'doMerge',
            ggLog: ggLog,
          ),
        ).thenAnswer((_) async => false);

        stubGitCommands();

        when(
          () => mockGgMergeDoMerge.get(
            directory: d,
            ggLog: ggLog,
            automerge: true,
            local: true,
          ),
        ).thenAnswer((_) async => true);

        when(
          () => mockGgState.writeSuccess(directory: d, key: 'doMerge'),
        ).thenAnswer((_) async {});

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
          ),
        ).called(1);
      });
    });
  });
}

class MockGgMergeDoMerge extends Mock implements gg_merge.DoMerge {}

class MockGgState extends Mock implements GgState {}

class MockMainBranch extends Mock implements gg_publish.MainBranch {}

class MockGgProcessWrapper extends Mock implements GgProcessWrapper {}
