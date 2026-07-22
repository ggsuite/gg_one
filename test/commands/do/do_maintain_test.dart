// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_one/gg_one.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

void main() {
  late Directory d;
  final messages = <String>[];
  final ggLog = messages.add;
  late CommandRunner<void> runner;
  late DoMaintain doMaintain;

  late MockDoUpgrade doUpgrade;

  // ...........................................................................
  void mockDoUpgrade({required bool success, bool majorVersions = false}) {
    doUpgrade.mockGet(
      result: null,
      doThrow: !success,
      directory: d,
      majorVersions: majorVersions,
      ggLog: null,
    );
  }

  // ...........................................................................
  void initMocks() {
    doUpgrade = MockDoUpgrade();
    mockDoUpgrade(success: true);
  }

  // ...........................................................................
  setUp(() async {
    d = await Directory.systemTemp.createTemp();
    registerFallbackValue(d);

    initMocks();

    doMaintain = DoMaintain(ggLog: ggLog, doUpgrade: doUpgrade);

    runner = CommandRunner<void>('gg', 'gg')..addCommand(doMaintain);
  });

  tearDown(() async {
    await d.delete(recursive: true);
  });

  // ...........................................................................
  group('DoMaintain', () {
    group('- main case', () {
      group('- should upgrade dependencies', () {
        tearDown(() {
          expect(messages[0], contains('⌛️ Upgrading dependencies'));
          expect(messages[1], contains('✅ Upgrading dependencies'));
        });

        test('- programmatically', () async {
          await doMaintain.exec(directory: d, ggLog: ggLog);
        });
        test('- via CLI', () async {
          await runner.run(['maintain', '-i', d.path]);
        });
      });
    });

    group('- edge cases', () {
      test('- should init with defaults', () {
        final doMaintain = DoMaintain(ggLog: ggLog);

        expect(doMaintain.name, 'maintain');
        expect(doMaintain.description, 'Upgrades the package dependencies.');
      });

      test('- should throw on upgrade failure', () async {
        mockDoUpgrade(success: false);

        expect(
          () => doMaintain.exec(directory: d, ggLog: ggLog),
          throwsA(isA<Exception>()),
        );
      });
    });
  });
}
