// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_one/src/tools/formatter.dart';
import 'package:gg_lang/gg_lang.dart';
import 'package:gg_process/gg_process.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

void main() {
  final messages = <String>[];
  late Directory tmpDir;
  late MockGgProcessWrapper processWrapper;

  setUp(() {
    messages.clear();
    tmpDir = Directory.systemTemp.createTempSync();
    processWrapper = MockGgProcessWrapper();
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  group('DartFormatter', () {
    test('runs "dart format . -o write --set-exit-if-changed"', () async {
      when(
        () => processWrapper.run(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));

      final formatter = DartFormatter(
        processWrapper: processWrapper,
        isGitHub: () => false,
      );
      await formatter.run(directory: tmpDir, ggLog: messages.add);

      final captured = verify(
        () => processWrapper.run(
          captureAny(),
          captureAny(),
          workingDirectory: captureAny(named: 'workingDirectory'),
        ),
      ).captured;
      expect(captured[0], 'dart');
      expect(captured[1], [
        'format',
        '.',
        '-o',
        'write',
        '--set-exit-if-changed',
      ]);
      expect(captured[2], tmpDir.path);
      expect(messages[0], contains('⌛️ Running "dart format"'));
      expect(messages[1], contains('✅ Running "dart format"'));
    });

    test('succeeds locally when files were rewritten', () async {
      when(
        () => processWrapper.run(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer(
        (_) async => ProcessResult(1, 1, 'Formatted lib/foo.dart', ''),
      );

      final formatter = DartFormatter(
        processWrapper: processWrapper,
        isGitHub: () => false,
      );

      await formatter.run(directory: tmpDir, ggLog: messages.add);
      expect(messages[1], contains('✅'));
    });

    test('throws on GitHub when files were rewritten', () async {
      when(
        () => processWrapper.run(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer(
        (_) async => ProcessResult(1, 1, 'Formatted lib/foo.dart', ''),
      );

      final formatter = DartFormatter(
        processWrapper: processWrapper,
        isGitHub: () => true,
      );

      await expectLater(
        () => formatter.run(directory: tmpDir, ggLog: messages.add),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('dart format failed.'),
          ),
        ),
      );
    });

    test('throws when the formatter exits with error and no files', () async {
      when(
        () => processWrapper.run(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 2, '', 'broken stderr'));

      final formatter = DartFormatter(
        processWrapper: processWrapper,
        isGitHub: () => false,
      );

      await expectLater(
        () => formatter.run(directory: tmpDir, ggLog: messages.add),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('dart format failed.'),
          ),
        ),
      );
    });

    test('defaults to real isGitHub detection when not injected', () {
      const formatter = DartFormatter();
      expect(formatter.processWrapper, isA<GgProcessWrapper>());
    });
  });

  group('TypeScriptFormatter', () {
    test('runs "eslint --fix" locally', () async {
      when(
        () => processWrapper.run(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));

      final formatter = TypeScriptFormatter(
        processWrapper: processWrapper,
        isGitHub: () => false,
        packageManager: (_) => TypeScriptPackageManager.pnpm,
      );
      await formatter.run(directory: tmpDir, ggLog: messages.add);

      final captured = verify(
        () => processWrapper.run(
          captureAny(),
          captureAny(),
          workingDirectory: captureAny(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).captured;
      expect(captured[0], 'pnpm');
      expect(captured[1], ['exec', 'eslint', '--fix']);
      expect(captured[2], tmpDir.path);
      expect(messages[0], contains('⌛️ Running "eslint"'));
      expect(messages[1], contains('✅ Running "eslint"'));
    });

    test('runs "eslint" (no --fix) on GitHub', () async {
      when(
        () => processWrapper.run(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));

      final formatter = TypeScriptFormatter(
        processWrapper: processWrapper,
        isGitHub: () => true,
        packageManager: (_) => TypeScriptPackageManager.npm,
      );
      await formatter.run(directory: tmpDir, ggLog: messages.add);

      final captured = verify(
        () => processWrapper.run(
          captureAny(),
          captureAny(),
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).captured;
      expect(captured[0], 'npx');
      expect(captured[1], ['eslint']);
    });

    test('throws and echoes tool output when eslint exits non-zero', () async {
      when(
        () => processWrapper.run(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer(
        (_) async => ProcessResult(1, 1, 'src/foo.ts: 2 problems', ''),
      );

      final formatter = TypeScriptFormatter(
        processWrapper: processWrapper,
        isGitHub: () => false,
        packageManager: (_) => TypeScriptPackageManager.pnpm,
      );

      await expectLater(
        () => formatter.run(directory: tmpDir, ggLog: messages.add),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Format check failed'),
          ),
        ),
      );
      expect(messages, contains('src/foo.ts: 2 problems'));
    });

    test('runs the package.json "format" script locally', () async {
      File(
        '${tmpDir.path}/package.json',
      ).writeAsStringSync('{"scripts":{"format":"prettier --write ."}}');
      when(
        () => processWrapper.run(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));

      final formatter = TypeScriptFormatter(
        processWrapper: processWrapper,
        isGitHub: () => false,
        packageManager: (_) => TypeScriptPackageManager.pnpm,
      );
      await formatter.run(directory: tmpDir, ggLog: messages.add);

      final captured = verify(
        () => processWrapper.run(
          captureAny(),
          captureAny(),
          workingDirectory: captureAny(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).captured;
      expect(captured[0], 'pnpm');
      expect(captured[1], ['run', 'format']);
      expect(messages[0], contains('⌛️ Running "pnpm run format"'));
      expect(messages[1], contains('✅ Running "pnpm run format"'));
    });

    test('runs the package.json "format:check" script on GitHub', () async {
      File(
        '${tmpDir.path}/package.json',
      ).writeAsStringSync('{"scripts":{"format:check":"prettier --check ."}}');
      when(
        () => processWrapper.run(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));

      final formatter = TypeScriptFormatter(
        processWrapper: processWrapper,
        isGitHub: () => true,
        packageManager: (_) => TypeScriptPackageManager.npm,
      );
      await formatter.run(directory: tmpDir, ggLog: messages.add);

      final captured = verify(
        () => processWrapper.run(
          captureAny(),
          captureAny(),
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).captured;
      expect(captured[0], 'npm');
      expect(captured[1], ['run', 'format:check']);
    });

    test('detects the package manager from the directory by default', () async {
      File('${tmpDir.path}/pnpm-lock.yaml').writeAsStringSync('');
      when(
        () => processWrapper.run(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));

      final formatter = TypeScriptFormatter(
        processWrapper: processWrapper,
        isGitHub: () => false,
      );
      await formatter.run(directory: tmpDir, ggLog: messages.add);

      final captured = verify(
        () => processWrapper.run(
          captureAny(),
          captureAny(),
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).captured;
      expect(captured[0], 'pnpm');
    });

    test('defaults processWrapper and isGitHub when not provided', () {
      const formatter = TypeScriptFormatter();
      expect(formatter.processWrapper, isA<GgProcessWrapper>());
    });
  });

  group('examples', () {
    test('provide real, usable instances', () {
      expect(DartFormatter.example(), isA<DartFormatter>());
      expect(TypeScriptFormatter.example(), isA<TypeScriptFormatter>());
    });
  });
}
