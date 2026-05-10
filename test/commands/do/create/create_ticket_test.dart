// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_one/gg_one.dart';
import 'package:gg_git/gg_git.dart';
import 'package:gg_process/gg_process.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

void main() {
  late Directory d;
  final messages = <String>[];
  final ggLog = messages.add;
  late CommandRunner<void> runner;
  late CreateTicket createTicket;
  late MockCanCheckout canCheckout;
  late MockIsPushed isPushed;
  late MockGgProcessWrapper processWrapper;

  setUp(() async {
    messages.clear();
    d = await Directory.systemTemp.createTemp();
    registerFallbackValue(d);
    canCheckout = MockCanCheckout();
    isPushed = MockIsPushed();
    processWrapper = MockGgProcessWrapper();
    canCheckout.mockExec(result: null, directory: d, ggLog: ggLog);
    createTicket = CreateTicket(
      ggLog: ggLog,
      canCheckout: canCheckout,
      isPushed: isPushed,
      processWrapper: processWrapper,
    );
    runner = CommandRunner<void>('gg', 'gg')..addCommand(createTicket);
  });

  tearDown(() async {
    await d.delete(recursive: true);
  });

  void mockGitCommand(
    List<String> args, {
    int exitCode = 0,
    String stderr = '',
  }) {
    when(
      () => processWrapper.run('git', args, workingDirectory: d.path),
    ).thenAnswer((_) async => ProcessResult(0, exitCode, '', stderr));
  }

  group('CreateTicket', () {
    test('should execute CanCheckout before git commands', () async {
      when(
        () => isPushed.get(
          directory: d,
          ggLog: ggLog,
          ignoreUnCommittedChanges: true,
        ),
      ).thenAnswer((_) async => true);

      mockGitCommand(['stash']);
      mockGitCommand(['checkout', '-b', 'feat_test']);
      mockGitCommand(['stash', 'apply']);

      await createTicket.exec(
        directory: d,
        ggLog: ggLog,
        branchName: 'feat_test',
      );

      verify(() => canCheckout.exec(directory: d, ggLog: ggLog)).called(1);
    });

    test('should reset soft when unpushed commits exist', () async {
      when(
        () => isPushed.get(
          directory: d,
          ggLog: ggLog,
          ignoreUnCommittedChanges: true,
        ),
      ).thenAnswer((_) async => false);

      mockGitCommand(['reset', '--soft', 'origin/main']);
      mockGitCommand(['stash']);
      mockGitCommand(['checkout', '-b', 'feat_test']);
      mockGitCommand(['stash', 'apply']);

      await createTicket.exec(
        directory: d,
        ggLog: ggLog,
        branchName: 'feat_test',
      );

      verify(() => canCheckout.exec(directory: d, ggLog: ggLog)).called(1);
      verify(
        () => isPushed.get(
          directory: d,
          ggLog: ggLog,
          ignoreUnCommittedChanges: true,
        ),
      ).called(1);
      verify(
        () => processWrapper.run('git', [
          'reset',
          '--soft',
          'origin/main',
        ], workingDirectory: d.path),
      ).called(1);
      verify(
        () => processWrapper.run('git', ['stash'], workingDirectory: d.path),
      ).called(1);
      verify(
        () => processWrapper.run('git', [
          'checkout',
          '-b',
          'feat_test',
        ], workingDirectory: d.path),
      ).called(1);
      verify(
        () => processWrapper.run('git', [
          'stash',
          'apply',
        ], workingDirectory: d.path),
      ).called(1);
    });

    test('should skip reset when everything is pushed', () async {
      when(
        () => isPushed.get(
          directory: d,
          ggLog: ggLog,
          ignoreUnCommittedChanges: true,
        ),
      ).thenAnswer((_) async => true);

      mockGitCommand(['stash']);
      mockGitCommand(['checkout', '-b', 'feat_test']);
      mockGitCommand(['stash', 'apply']);

      await createTicket.exec(
        directory: d,
        ggLog: ggLog,
        branchName: 'feat_test',
      );

      verify(() => canCheckout.exec(directory: d, ggLog: ggLog)).called(1);
      verifyNever(
        () => processWrapper.run('git', [
          'reset',
          '--soft',
          'origin/main',
        ], workingDirectory: d.path),
      );
      verify(
        () => processWrapper.run('git', ['stash'], workingDirectory: d.path),
      ).called(1);
      verify(
        () => processWrapper.run('git', [
          'checkout',
          '-b',
          'feat_test',
        ], workingDirectory: d.path),
      ).called(1);
      verify(
        () => processWrapper.run('git', [
          'stash',
          'apply',
        ], workingDirectory: d.path),
      ).called(1);
    });

    test('should support CLI usage', () async {
      when(
        () => isPushed.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          ignoreUnCommittedChanges: true,
        ),
      ).thenAnswer((_) async => true);

      mockGitCommand(['stash']);
      mockGitCommand(['checkout', '-b', 'feat_cli']);
      mockGitCommand(['stash', 'apply']);

      await runner.run([
        'ticket',
        '-i',
        d.path,
        '-b',
        'feat_cli',
        '-m',
        'CLI message',
      ]);

      verify(
        () => processWrapper.run('git', [
          'checkout',
          '-b',
          'feat_cli',
        ], workingDirectory: d.path),
      ).called(1);

      final ticketFile = File('${d.path}${Platform.pathSeparator}.ticket');
      expect(ticketFile.existsSync(), isTrue);

      final content =
          jsonDecode(ticketFile.readAsStringSync()) as Map<String, dynamic>;
      expect(content['issue_id'], equals('feat_cli'));
      expect(content['description'], equals('CLI message'));
    });

    test('should apply stash and rethrow when checkout fails', () async {
      when(
        () => isPushed.get(
          directory: d,
          ggLog: ggLog,
          ignoreUnCommittedChanges: true,
        ),
      ).thenAnswer((_) async => true);

      mockGitCommand(['stash']);
      mockGitCommand(
        ['checkout', '-b', 'feat_test'],
        exitCode: 1,
        stderr: 'Checkout error',
      );
      mockGitCommand(['stash', 'apply']);

      await expectLater(
        () => createTicket.exec(
          directory: d,
          ggLog: ggLog,
          branchName: 'feat_test',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'toString()',
            'Exception: git checkout -b feat_test failed: Checkout error',
          ),
        ),
      );

      verify(() => canCheckout.exec(directory: d, ggLog: ggLog)).called(1);
      verify(
        () => processWrapper.run('git', ['stash'], workingDirectory: d.path),
      ).called(1);
      verify(
        () => processWrapper.run('git', [
          'checkout',
          '-b',
          'feat_test',
        ], workingDirectory: d.path),
      ).called(1);
      verify(
        () => processWrapper.run('git', [
          'stash',
          'apply',
        ], workingDirectory: d.path),
      ).called(1);
    });

    test('should throw when CanCheckout fails', () async {
      canCheckout.mockExec(
        result: null,
        directory: d,
        ggLog: ggLog,
        doThrow: true,
        message: 'Cannot checkout.',
      );

      await expectLater(
        () => createTicket.exec(
          directory: d,
          ggLog: ggLog,
          branchName: 'feat_test',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'toString()',
            contains('Cannot checkout.'),
          ),
        ),
      );

      verifyNever(
        () => processWrapper.run(
          'git',
          any(),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      );
    });

    test('should throw when stash fails', () async {
      when(
        () => isPushed.get(
          directory: d,
          ggLog: ggLog,
          ignoreUnCommittedChanges: true,
        ),
      ).thenAnswer((_) async => true);

      mockGitCommand(['stash'], exitCode: 1, stderr: 'Some error');

      expect(
        () => createTicket.exec(
          directory: d,
          ggLog: ggLog,
          branchName: 'feat_test',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'toString()',
            'Exception: git stash failed: Some error',
          ),
        ),
      );
    });

    test('should throw when branch name is missing', () async {
      expect(
        () => createTicket.exec(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'toString()',
            'Exception: Missing branch name. '
                'Run again with --branch-name <branch_name>.',
          ),
        ),
      );
    });

    test('should throw on CLI when message is missing', () async {
      expect(
        () => runner.run(['ticket', '-i', d.path, '-b', 'feat_cli']),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'toString()',
            'Exception: Missing message. Run again with --message <message>.',
          ),
        ),
      );
    });

    test(
      'should write .ticket file when message is provided programmatically',
      () async {
        when(
          () => isPushed.get(
            directory: d,
            ggLog: ggLog,
            ignoreUnCommittedChanges: true,
          ),
        ).thenAnswer((_) async => true);

        mockGitCommand(['stash']);
        mockGitCommand(['checkout', '-b', 'feat_test']);
        mockGitCommand(['stash', 'apply']);

        await createTicket.exec(
          directory: d,
          ggLog: ggLog,
          branchName: 'feat_test',
          message: 'Programmatic message',
        );

        final ticketFile = File('${d.path}${Platform.pathSeparator}.ticket');
        expect(ticketFile.existsSync(), isTrue);

        final content =
            jsonDecode(ticketFile.readAsStringSync()) as Map<String, dynamic>;
        expect(content['issue_id'], equals('feat_test'));
        expect(content['description'], equals('Programmatic message'));
      },
    );

    test(
      'should not write .ticket file when message is null programmatically',
      () async {
        when(
          () => isPushed.get(
            directory: d,
            ggLog: ggLog,
            ignoreUnCommittedChanges: true,
          ),
        ).thenAnswer((_) async => true);

        mockGitCommand(['stash']);
        mockGitCommand(['checkout', '-b', 'feat_test']);
        mockGitCommand(['stash', 'apply']);

        await createTicket.exec(
          directory: d,
          ggLog: ggLog,
          branchName: 'feat_test',
        );

        final ticketFile = File('${d.path}${Platform.pathSeparator}.ticket');
        expect(ticketFile.existsSync(), isFalse);
      },
    );
  });
}

class MockGgProcessWrapper extends Mock implements GgProcessWrapper {}
