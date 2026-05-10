// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_one/gg_one.dart';
import 'package:gg_publish/gg_publish.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

void main() {
  late Directory d;
  late MockIsUpgraded isUpgraded;
  late DidUpgrade didUpgrade;
  late CommandRunner<void> runner;

  final messages = <String>[];
  final ggLog = messages.add;

  // ...........................................................................
  setUp(() async {
    messages.clear();
    d = await Directory.systemTemp.createTemp();
    registerFallbackValue(d);
    isUpgraded = MockIsUpgraded();
    didUpgrade = DidUpgrade(ggLog: ggLog, isUpgraded: isUpgraded);
    runner = CommandRunner<void>('test', 'test')..addCommand(didUpgrade);
  });

  tearDown(() async {
    await d.delete(recursive: true);
  });

  // ...........................................................................
  group('DidUpgrade', () {
    group('should check', () {
      group('if everything is upgraded', () {
        for (final viaCli in [true, false]) {
          test('via CLI and programmatically', () async {
            isUpgraded.mockGet(result: true);

            if (viaCli == false) {
              await didUpgrade.exec(directory: d, ggLog: ggLog);
            } else {
              await runner.run(['upgrade', '-i', d.path]);
            }
            expect(messages[0], contains('⌛️ Everything is upgraded'));
            expect(messages[1], contains('✅ Everything is upgraded'));
          });
        }
      });
    });

    group('should handle edge cases: ', () {
      test('instantiate without optional parameters', () {
        expect(() => DidUpgrade(ggLog: ggLog), returnsNormally);
      });
    });
  });

  // #########################################################################
  group('MockDidUpgrade', () {
    group('mockGet', () {
      group('should mock get', () {
        test('with ggLog', () async {
          final didUpgrade = MockDidUpgrade();
          didUpgrade.mockGet(
            result: true,
            directory: d,
            ggLog: ggLog,
            majorVersions: true,
          );

          final result = await didUpgrade.get(
            directory: d,
            ggLog: ggLog,
            majorVersions: true,
          );

          expect(result, isTrue);
          expect(messages[0], contains('✅ DidUpgrade'));
        });

        test('without ggLog', () async {
          final didUpgrade = MockDidUpgrade();
          didUpgrade.mockGet(
            result: true,
            directory: d,
            majorVersions: true,
            ggLog: null, // <-- ggLog is null
          );

          final result = await didUpgrade.get(
            directory: d,
            majorVersions: true,
            ggLog: (_) {},
          );

          expect(result, isTrue);
          expect(messages, isEmpty);
        });
      });
    });
  });
}
