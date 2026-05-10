// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_one/gg_one.dart';
import 'package:test/test.dart';

void main() {
  final messages = <String>[];
  late CommandRunner<void> runner;
  final check = Check(ggLog: messages.add);

  setUp(() {
    messages.clear();
    runner = CommandRunner<void>('gg', 'Description goes here.');
    runner.addCommand(check);
  });

  group('Check', () {
    // .......................................................................
    test('should show all sub commands', () async {
      // Show sub commands defined within commands/check?
      final (subCommands, errorMessage) = await missingSubCommands(
        directory: Directory('lib/src/commands/check'),
        command: check,
        additionalSubCommands: [
          'is-committed',
          'is-pushed',
          'is-versioned',
          'is-published',
        ],
      );

      expect(subCommands, isEmpty, reason: errorMessage);
    });
  });
}
