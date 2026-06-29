// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_one/gg_one.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_process/gg_process.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockGgProcessWrapper extends Mock implements GgProcessWrapper {}

void main() {
  late Directory d;
  final messages = <String>[];
  final ggLog = messages.add;
  late MockGgProcessWrapper processWrapper;
  late DoCheckout doCheckout;
  late CommandRunner<void> runner;

  void mockGit(
    List<String> args, {
    int exitCode = 0,
    String stdout = '',
    String stderr = '',
  }) {
    when(
      () => processWrapper.run(
        'git',
        args,
        runInShell: true,
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer((_) async => ProcessResult(0, exitCode, stdout, stderr));
  }

  setUp(() async {
    messages.clear();
    d = await Directory.systemTemp.createTemp();
    processWrapper = MockGgProcessWrapper();
    doCheckout = DoCheckout(ggLog: ggLog, processWrapper: processWrapper);
    runner = CommandRunner<void>('gg', 'gg')..addCommand(doCheckout);
  });

  tearDown(() async {
    await d.delete(recursive: true);
  });

  group('DoCheckout', () {
    group('constructor', () {
      test('initializes with defaults', () {
        final instance = DoCheckout(ggLog: ggLog);
        expect(instance.name, 'checkout');
        expect(
          instance.description,
          'Check out the branch belonging to a ticket.',
        );
      });
    });

    test('fetches then checks out the branch', () async {
      mockGit(const ['fetch']);
      mockGit(['checkout', 'my-branch']);

      await doCheckout.get(directory: d, ggLog: ggLog, branch: 'my-branch');

      verifyInOrder([
        () => processWrapper.run(
          'git',
          const ['fetch'],
          runInShell: true,
          workingDirectory: d.path,
        ),
        () => processWrapper.run(
          'git',
          ['checkout', 'my-branch'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ]);
      expect(messages.last, green('Checked out my-branch.'));
    });

    test('reads the branch name from the positional argument', () async {
      mockGit(const ['fetch']);
      mockGit(['checkout', 'feat_cli']);

      await runner.run(['checkout', '-i', d.path, 'feat_cli']);

      verify(
        () => processWrapper.run(
          'git',
          ['checkout', 'feat_cli'],
          runInShell: true,
          workingDirectory: d.path,
        ),
      ).called(1);
    });

    test('logs each git command when verbose', () async {
      mockGit(const ['fetch']);
      mockGit(['checkout', 'feat_cli']);

      await runner.run(['checkout', '-i', d.path, '-v', 'feat_cli']);

      expect(
        messages,
        containsAll(<String>['\$ git fetch', '\$ git checkout feat_cli']),
      );
    });

    test('throws a usage exception when no name is given', () async {
      await expectLater(
        runner.run(['checkout', '-i', d.path]),
        throwsA(isA<UsageException>()),
      );
    });

    test('throws when fetch fails', () async {
      mockGit(const ['fetch'], exitCode: 1, stderr: 'no network');

      await expectLater(
        doCheckout.get(directory: d, ggLog: ggLog, branch: 'x'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Failed to fetch: no network'),
          ),
        ),
      );
    });

    test('throws with stdout when checkout fails without stderr', () async {
      mockGit(const ['fetch']);
      mockGit(['checkout', 'x'], exitCode: 1, stdout: 'pathspec x not found');

      await expectLater(
        doCheckout.get(directory: d, ggLog: ggLog, branch: 'x'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Failed to checkout x: pathspec x not found'),
          ),
        ),
      );
    });

    group('exec', () {
      test('delegates to get', () async {
        mockGit(const ['fetch']);
        mockGit(['checkout', 'b']);

        await doCheckout.exec(directory: d, ggLog: ggLog, branch: 'b');

        verify(
          () => processWrapper.run(
            'git',
            ['checkout', 'b'],
            runInShell: true,
            workingDirectory: d.path,
          ),
        ).called(1);
      });
    });
  });
}
