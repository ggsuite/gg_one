// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_one/gg_one.dart';
import 'package:gg_git/gg_git.dart';
import 'package:gg_git/gg_git_test_helpers.dart';
import 'package:gg_publish/gg_publish.dart';

import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

// .............................................................................
void main() {
  late Directory d;
  late Checks commands;
  final messages = <String>[];

  // Strip the colors so the expectations stay readable. A function
  // declaration, not a closure variable: mocktail matches the ggLog
  // argument by identity, and every tear-off of it must be the same.
  void ggLog(String msg) => messages.add(rmC(msg));
  late CanPush push;

  // ...........................................................................
  void mockCommands() {
    when(
      () => commands.isCommitted.exec(directory: d, ggLog: ggLog),
    ).thenAnswer((_) async {
      messages.add('did commit');
      return true;
    });
  }

  // ...........................................................................
  setUp(() async {
    commands = Checks(
      ggLog: ggLog,
      isCommitted: MockIsCommitted(),
      isUpgraded: MockIsUpgraded(),
    );

    push = CanPush(ggLog: ggLog, checkCommands: commands);
    d = Directory.systemTemp.createTempSync();
    await initGit(d);
    mockCommands();
  });

  // ...........................................................................
  tearDown(() {
    d.deleteSync(recursive: true);
  });

  // ...........................................................................
  group('Can', () {
    group('Push', () {
      group('constructor', () {
        test('with defaults', () {
          final c = CanPush(ggLog: ggLog);
          expect(c.name, 'push');
          expect(c.description, 'Check if this repo can be pushed');
        });
      });
      group('run(directory)', () {
        test('should check if everything is upgraded and commited', () async {
          await addAndCommitSampleFile(d);
          await push.exec(directory: d, ggLog: ggLog);
          expect(messages[0], contains('Can push?'));
          expect(messages[1], 'did commit');
        });
      });
    });
  });
}
