// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_one/gg_one.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_git/gg_git.dart';
import 'package:test/test.dart';

void main() {
  final messages = <String>[];
  final ggLog = messages.add;

  late CommandRunner<void> runner;
  late Info info;

  setUp(() {
    info = Info(ggLog: ggLog);
    runner = CommandRunner<void>('gg', 'gg)')..addCommand(info);
  });

  void expectCommand(Command<dynamic> command) {
    final message = messages[0];
    expect(message, contains(command.name));
    expect(message, contains(command.description));
  }

  group('Info', () {
    group('run()', () {
      test('should provide various information commands', () async {
        await capturePrint(
          ggLog: ggLog,
          code: () => runner.run(['info', '--help']),
        );

        expect(messages, hasLength(1));
        expectCommand(info);
        expectCommand(ModifiedFiles(ggLog: ggLog));
        expectCommand(LastChangesHash(ggLog: ggLog));
      });
    });
  });
}
