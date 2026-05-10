// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_one/gg_one.dart';
import 'package:gg_process/gg_process.dart';
import 'package:path/path.dart';
import 'package:recase/recase.dart';
import 'package:test/test.dart';

void main() {
  final messages = <String>[];
  const processWrapper = GgProcessWrapper();

  setUp(() {
    messages.clear();
  });

  group('gg()', () {
    // #########################################################################
    group('gg_one', () {
      final gg = Gg(ggLog: messages.add, processWrapper: processWrapper);

      final CommandRunner<void> runner = CommandRunner<void>(
        'gg_one',
        'Description goes here.',
      )..addCommand(gg);

      test('should allow to run the code from command line', () async {
        final tmp = Directory.systemTemp.createTempSync();
        File('${tmp.path}/pubspec.yaml').writeAsStringSync('name: foo\n');

        await capturePrint(
          ggLog: messages.add,
          code: () =>
              runner.run(['gg_one', 'check', 'analyze', '--input', tmp.path]),
        );

        await tmp.delete(recursive: true);
        expect(messages.first, contains('⌛️ Running "dart analyze"'));
        expect(messages.last, contains('✅ Running "dart analyze"'));
      });

      // .......................................................................
      test('should show all sub commands', () async {
        // Iterate all files in lib/src/commands
        // and check if they are added to the command runner
        // and if they are added to the help message
        final subCommands = Directory('lib/src/commands')
            .listSync(recursive: false)
            .where((file) => file.path.endsWith('.dart'))
            .map(
              (e) => basename(e.path)
                  .replaceAll('.dart', '')
                  .replaceAll('_', '-')
                  .replaceAll('gg-', ''),
            )
            .toList();

        await capturePrint(
          ggLog: messages.add,
          code: () async => await runner.run(['gg_one', '--help']),
        );

        for (final subCommand in subCommands) {
          final subCommandStr = subCommand.pascalCase;

          expect(
            hasLog(messages, subCommand),
            isTrue,
            reason:
                '\nMissing subcommand "$subCommandStr"\n'
                'Please open  "lib/src/gg.dart" and add\n'
                '"addSubcommand($subCommandStr(ggLog: ggLog));',
          );
        }
      });
    });
  });
}
