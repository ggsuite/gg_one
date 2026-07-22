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
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

void main() {
  late Directory d;
  late CanUpgrade canUpgrade;
  late CommandRunner<void> runner;

  final messages = <String>[];
  final ggLog = messages.add;

  // ...........................................................................
  setUp(() async {
    messages.clear();
    d = await Directory.systemTemp.createTemp();
    await initGit(d);
    await addAndCommitSampleFile(d);
    registerFallbackValue(d);
    canUpgrade = CanUpgrade(ggLog: ggLog);
    runner = CommandRunner<void>('test', 'test')..addCommand(canUpgrade);
  });

  tearDown(() async {
    await d.delete(recursive: true);
  });

  // ...........................................................................
  group('CanUpgrade', () {
    group('should succeed', () {
      tearDown(() {
        expect(messages[0], yellow('Can upgrade?'));
      });

      test('programmatically', () async {
        await canUpgrade.exec(directory: d, ggLog: ggLog);
      });

      test('via CLI', () async {
        await runner.run(['upgrade', d.path]);
      });
    });

    group('edge cases', () {
      test('initialized with default arguments', () {
        final canUpgrade = CanUpgrade(ggLog: ggLog);
        expect(canUpgrade.name, 'upgrade');
        expect(
          canUpgrade.description,
          'Is the package ready to get a dependeny upgrade?',
        );
      });
    });
  });
}
