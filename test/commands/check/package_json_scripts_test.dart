// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_one/gg_one.dart';
import 'package:test/test.dart';

void main() {
  final messages = <String>[];
  late CommandRunner<void> runner;
  late Directory tmpDir;

  setUp(() {
    messages.clear();
    runner = CommandRunner<void>('test', 'test');
    runner.addCommand(CheckPackageJsonScripts(ggLog: messages.add));
    tmpDir = Directory.systemTemp.createTempSync();
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  const validScripts = <String, String>{
    'test': 'vitest run',
    'build': 'tsc',
    'lint': 'eslint',
    'prepublish': 'npm run test && npm run build',
  };

  // Writes a TypeScript project (package.json + tsconfig.json) declaring the
  // given [scripts].
  void writeTsProject(Map<String, String> scripts) {
    final entries = scripts.entries
        .map((e) => '"${e.key}": "${e.value}"')
        .join(', ');
    File(
      '${tmpDir.path}/package.json',
    ).writeAsStringSync('{"name": "ts", "scripts": {$entries}}');
    File('${tmpDir.path}/tsconfig.json').writeAsStringSync('{}');
  }

  Future<void> run() =>
      runner.run(['package-json-scripts', '--input', tmpDir.path]);

  group('CheckPackageJsonScripts', () {
    group('skips', () {
      test('a Dart project', () async {
        File('${tmpDir.path}/pubspec.yaml').writeAsStringSync('name: foo\n');
        await run();
        expect(messages, isEmpty);
      });

      test('a directory without a recognizable manifest', () async {
        await run();
        expect(messages, isEmpty);
      });
    });

    group('succeeds', () {
      test('when all required scripts are present and prepublish runs '
          'test and build', () async {
        writeTsProject(validScripts);
        await run();
        expect(messages.any((m) => m.contains('✅')), isTrue);
      });

      test('for a bridge, treated as TypeScript', () async {
        // A bridge ships pubspec.yaml AND package.json + tsconfig.json.
        writeTsProject(validScripts);
        File('${tmpDir.path}/pubspec.yaml').writeAsStringSync('name: b\n');
        await run();
        expect(messages.any((m) => m.contains('✅')), isTrue);
      });
    });

    group('throws', () {
      test('when a required script is missing', () async {
        final scripts = Map<String, String>.from(validScripts)..remove('build');
        writeTsProject(scripts);
        await expectLater(
          run(),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              allOf(contains('missing required scripts'), contains('build')),
            ),
          ),
        );
      });

      test('when prepublish does not run test', () async {
        final scripts = Map<String, String>.from(validScripts)
          ..['prepublish'] = 'npm run build';
        writeTsProject(scripts);
        await expectLater(
          run(),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              allOf(contains('prepublish'), contains('test')),
            ),
          ),
        );
      });

      test('when prepublish does not run build', () async {
        final scripts = Map<String, String>.from(validScripts)
          ..['prepublish'] = 'npm run test';
        writeTsProject(scripts);
        await expectLater(
          run(),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              allOf(contains('prepublish'), contains('build')),
            ),
          ),
        );
      });
    });

    test('example provides a real instance', () {
      expect(CheckPackageJsonScripts.example(), isA<CheckPackageJsonScripts>());
    });
  });
}
