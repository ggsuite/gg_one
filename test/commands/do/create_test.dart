// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_one/gg_one.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:test/test.dart';

void main() {
  late Directory d;
  late Create createCommand;
  final messages = <String>[];
  late CommandRunner<void> runner;

  setUp(() {
    d = Directory.systemTemp.createTempSync();
    messages.clear();
    createCommand = Create(ggLog: messages.add);
    runner = CommandRunner<void>('test', 'test')..addCommand(createCommand);
  });

  tearDown(() {
    d.deleteSync(recursive: true);
  });

  group('Create', () {
    test('should show ticket as subcommand', () async {
      await capturePrint(
        code: () async {
          await runner.run(['create', '--help']);
        },
        ggLog: messages.add,
      );

      expect(
        messages.first,
        contains('Create development artifacts like ticket branches.'),
      );
      expect(messages.first, contains('ticket'));
    });
  });
}
