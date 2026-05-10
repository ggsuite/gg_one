// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_one/src/commands/can.dart';
import 'package:test/test.dart';

void main() {
  late Directory d;
  late Can can;
  final messages = <String>[];
  late CommandRunner<void> runner;

  setUp(() {
    d = Directory.systemTemp.createTempSync();
    messages.clear();
    can = Can(ggLog: messages.add);
    runner = CommandRunner<void>('test', 'test')..addCommand(can);
  });

  tearDown(() {
    d.deleteSync(recursive: true);
  });

  group('Can', () {
    test('should work fine', () async {
      await capturePrint(
        code: () async {
          await runner.run(['can', '--help']);
        },
        ggLog: messages.add,
      );

      expect(
        messages.first,
        contains('Checks if you can commit, push, publish'),
      );
    });
  });
}
