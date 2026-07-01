// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_one/gg_one.dart';
import 'package:gg_process/gg_process.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

void main() {
  final messages = <String>[];
  late GgProcessWrapper processWrapper;
  late NpmLoggedIn npmLoggedIn;
  late CommandRunner<void> runner;
  late Directory d;

  // Writes a TypeScript package (package.json + tsconfig.json). When [private]
  // is true, the package.json sets `"private": true` (publish target `none`).
  // A pnpm-lock.yaml makes pnpm the detected package manager.
  void writeTsProject({bool private = false}) {
    final privateField = private ? '"private": true, ' : '';
    File(
      join(d.path, 'package.json'),
    ).writeAsStringSync('{"name": "ts", $privateField"version": "1.0.0"}');
    File(join(d.path, 'tsconfig.json')).writeAsStringSync('{}');
    File(join(d.path, 'pnpm-lock.yaml')).writeAsStringSync('');
  }

  void stubWhoami({
    required int exitCode,
    String stdout = '',
    String stderr = '',
  }) {
    when(
      () => processWrapper.run(
        'pnpm',
        const ['whoami'],
        workingDirectory: d.path,
        runInShell: true,
      ),
    ).thenAnswer((_) async => ProcessResult(0, exitCode, stdout, stderr));
  }

  Future<void> run() => runner.run(['npm-logged-in', '--input', d.path]);

  setUp(() {
    messages.clear();
    processWrapper = MockGgProcessWrapper();
    npmLoggedIn = NpmLoggedIn(
      ggLog: messages.add,
      processWrapper: processWrapper,
    );
    runner = CommandRunner<void>('test', 'test')..addCommand(npmLoggedIn);
    d = Directory.systemTemp.createTempSync('npm_logged_in_test');
  });

  tearDown(() {
    d.deleteSync(recursive: true);
  });

  group('NpmLoggedIn', () {
    group('skips (no npm authentication needed)', () {
      test('for a Dart package (pub.dev target)', () async {
        File(join(d.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
        await run();
        // A single skip message, and whoami is never invoked.
        expect(messages.single, contains('✅ Skipping npm auth check'));
        expect(messages.single, contains('pub.dev'));
      });

      test('for a private TypeScript package (none target)', () async {
        writeTsProject(private: true);
        await run();
        expect(messages.single, contains('✅ Skipping npm auth check'));
        expect(messages.single, contains('none'));
      });
    });

    group('for an npm package', () {
      test('succeeds when whoami succeeds', () async {
        writeTsProject();
        stubWhoami(exitCode: 0, stdout: 'goeran');
        await run();
        expect(messages.any((m) => m.contains('⌛️ Logged in to npm')), isTrue);
        expect(messages.any((m) => m.contains('✅ Logged in to npm')), isTrue);
      });

      test('throws with the stderr detail when whoami fails', () async {
        writeTsProject();
        stubWhoami(exitCode: 1, stderr: '401 Unauthorized');
        await expectLater(
          run(),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              allOf(
                contains('Not logged in'),
                contains('pnpm whoami failed: 401 Unauthorized'),
                contains('pnpm login'),
              ),
            ),
          ),
        );
        expect(messages.any((m) => m.contains('❌ Logged in to npm')), isTrue);
      });

      test('falls back to stdout when stderr is empty', () async {
        writeTsProject();
        stubWhoami(exitCode: 1, stdout: 'ERR whoami on stdout');
        await expectLater(
          run(),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('ERR whoami on stdout'),
            ),
          ),
        );
      });
    });

    test('example provides a real instance', () {
      expect(NpmLoggedIn.example(), isA<NpmLoggedIn>());
    });
  });
}
