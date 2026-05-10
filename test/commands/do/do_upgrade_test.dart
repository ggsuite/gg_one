// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_one/gg_one.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_git/gg_git_test_helpers.dart';
import 'package:gg_process/gg_process.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

void main() {
  late Directory d;
  final messages = <String>[];
  final ggLog = messages.add;
  late CommandRunner<void> runner;
  late DoUpgrade doUpgrade;

  // ...........................................................................
  late GgState? state;
  late MockDidUpgrade didUpgrade;
  late MockCanUpgrade canUpgrade;
  late MockGgProcessWrapper processWrapper;
  late MockCanCommit canCommit;

  // ...........................................................................
  void initMocks() {
    registerFallbackValue(d);
    state = GgState(ggLog: ggLog);
    didUpgrade = MockDidUpgrade();
    canUpgrade = MockCanUpgrade();
    processWrapper = MockGgProcessWrapper();
    canCommit = MockCanCommit();
  }

  // ...........................................................................
  void initDoUpgrade() {
    doUpgrade = DoUpgrade(
      ggLog: ggLog,
      state: state,
      didUpgrade: didUpgrade,
      canUpgrade: canUpgrade,
      processWrapper: processWrapper,
      canCommit: canCommit,
    );

    runner.addCommand(doUpgrade);
  }

  // ...........................................................................
  void mockDartPubUpgrade({
    bool majorVersions = false,
    int exitCode = 0,
    String stdout = '',
    String stderr = '',
    bool upgradingCausesChange = true,
  }) {
    when(
      () => processWrapper.run('dart', [
        'pub',
        'upgrade',
        if (majorVersions) '--major-versions',
      ], workingDirectory: d.path),
    ).thenAnswer((_) async {
      if (upgradingCausesChange) {
        await updateSampleFileWithoutCommitting(d);
      }

      return ProcessResult(0, exitCode, stdout, stderr);
    });
  }

  // ...........................................................................
  void mockCanCommit({bool success = true}) {
    canCommit.mockExec(
      result: null,
      directory: d,
      ggLog: ggLog,
      doThrow: !success,
      message: 'CanCommit failed.',
      force: true,
      saveState: null,
    );
  }

  // ...........................................................................
  void initDefaultMocks() {
    didUpgrade.mockGet(
      result: false,
      directory: d,
      ggLog: null,
      majorVersions: false,
    );

    canUpgrade.mockExec(result: null, directory: d, ggLog: ggLog);
    mockCanCommit();
    mockDartPubUpgrade();
  }

  // ...........................................................................
  setUp(() async {
    d = await Directory.systemTemp.createTemp();
    await initGit(d);
    await addAndCommitSampleFile(d);

    messages.clear();
    runner = CommandRunner<void>('gg', 'gg');
    initMocks();
    initDoUpgrade();
    initDefaultMocks();
  });

  tearDown(() async {
    await d.delete(recursive: true);
  });

  // ...........................................................................
  group('DoUpgrade', () {
    group('- main case', () {
      group('- should run »dart pub upggrade», '
          'check if everything still runs (canCommit) '
          'and finally commit and publish changes', () {
        void check() {
          expect(messages[0], contains('✅ CanUpgrade'));
          expect(messages[1], contains('⌛️ Run »dart pub upgrade«'));
          expect(messages[2], contains('✅ Run »dart pub upgrade«'));
          expect(messages[3], contains('✅ CanCommit'));
        }

        test('- programmatically', () async {
          await doUpgrade.exec(directory: d, ggLog: ggLog);
          check();
        });

        test('- via CLI', () async {
          await runner.run(['upgrade', '-i', d.path]);
          check();
        });
      });
    });

    group('- edge cases', () {
      group('- should fail', () {
        group('- when preconditions for can upgrade are not met', () {
          setUp(() {
            // Let canUpgrade fail
            canUpgrade.mockExec(
              result: null,
              directory: d,
              doThrow: true, // <- Throws
              message: 'CanUpgrade failed',
            );
          });

          Future<void> perform(Future<void> testCode) async {
            late String exception;
            try {
              await testCode;
            } catch (e) {
              exception = e.toString();
            }
            expect(exception, contains('CanUpgrade failed'));
          }

          test('- programmatically', () async {
            await perform(doUpgrade.exec(directory: d, ggLog: ggLog));
          });

          test('- via CLI', () async {
            await perform(runner.run(['upgrade', d.path, '-i', d.path]));
          });
        });

        test('- when »dart pub upgrade« exists with an error', () async {
          mockDartPubUpgrade(exitCode: 1, stderr: 'Something went wrong');

          late String exception;
          try {
            await doUpgrade.exec(directory: d, ggLog: ggLog);
          } catch (e) {
            exception = e.toString();
          }
          expect(
            exception,
            contains('»dart pub upgrade« failed: Something went wrong'),
          );
        });
      });

      group('- should do nothing', () {
        group('- when everything is already upgraded', () {
          setUp(() {
            // Let's say didUpgrade returns true
            didUpgrade.mockGet(
              result: true,
              directory: d,
              majorVersions: false,
            );
          });

          void check() {
            expect(messages.last, yellow('Everything is already up to date.'));
          }

          test('- programmatically', () async {
            await doUpgrade.exec(directory: d, ggLog: ggLog);
            check();
          });

          test('- via CLI', () async {
            await runner.run(['upgrade', d.path, '-i', d.path]);
            check();
          });
        });
      });

      group('- should not commit and publish ', () {
        test('when nothing was changed by »dart pub upgrade«', () async {
          mockDartPubUpgrade(upgradingCausesChange: false);
          await doUpgrade.exec(directory: d, ggLog: ggLog);
          final allMessages = messages.join('\n');
          expect(allMessages, isNot(contains('✅ DoCommit')));
          expect(allMessages, isNot(contains('✅ DoPublish')));
        });
      });

      test(
        '- should require fixing errors happening through updating',
        () async {
          mockCanCommit(success: false);

          late String exception;
          try {
            await doUpgrade.exec(directory: d, ggLog: ggLog);
          } catch (e) {
            exception = e.toString();
          }

          final message = red(
            'After the update tests are not running anymore. '
            'Please run ${blue('»gg can commit«')} and try again.',
          );

          expect(exception, contains(message));
        },
      );

      group('- should allow to upgrade major versions', () {
        setUp(() {
          mockDartPubUpgrade(majorVersions: true);
          didUpgrade.mockGet(
            result: false,
            directory: d,
            ggLog: null,
            majorVersions: true, // <- Major versions
          );
        });

        tearDown(() {
          expect(
            messages[1],
            contains('⌛️ Run »dart pub upgrade --major-versions«'),
          );

          expect(
            messages[2],
            contains('✅ Run »dart pub upgrade --major-versions«'),
          );
        });

        test('- programmatically', () async {
          await doUpgrade.exec(directory: d, ggLog: ggLog, majorVersions: true);
        });

        test('- via CLI', () async {
          await runner.run(['upgrade', '-i', d.path, '--major-versions']);
        });
      });

      test('- should init DoUpgrade with default params', () {
        expect(() => DoUpgrade(ggLog: ggLog), returnsNormally);
      });
    });
  });

  // #########################################################################
  group('MockDoUpgrade', () {
    group('mockExec', () {
      group('should mock exec', () {
        test('with ggLog', () async {
          final didUpgrade = MockDoUpgrade();
          didUpgrade.mockExec(
            result: null,
            directory: d,
            ggLog: ggLog,
            majorVersions: true,
          );

          await didUpgrade.exec(
            directory: d,
            ggLog: ggLog,
            majorVersions: true,
          );

          expect(messages[0], contains('✅ DoUpgrade'));
        });

        test('without ggLog', () async {
          final didUpgrade = MockDoUpgrade();
          didUpgrade.mockExec(
            result: null,
            directory: d,
            majorVersions: true,
            ggLog: null, // <-- ggLog is null
          );

          await didUpgrade.exec(
            directory: d,
            majorVersions: true,
            ggLog: (_) {},
          );

          expect(messages, isEmpty);
        });
      });
    });

    group('mockGet', () {
      group('should mock get', () {
        test('with ggLog', () async {
          final didUpgrade = MockDoUpgrade();
          didUpgrade.mockGet(
            result: null,
            directory: d,
            ggLog: ggLog,
            majorVersions: true,
          );

          await didUpgrade.get(directory: d, ggLog: ggLog, majorVersions: true);

          expect(messages[0], contains('✅ DoUpgrade'));
        });

        test('without ggLog', () async {
          final didUpgrade = MockDoUpgrade();
          didUpgrade.mockGet(
            result: null,
            directory: d,
            majorVersions: true,
            ggLog: null, // <-- ggLog is null
          );

          await didUpgrade.get(
            directory: d,
            majorVersions: true,
            ggLog: (_) {},
          );

          expect(messages, isEmpty);
        });
      });
    });
  });
}
