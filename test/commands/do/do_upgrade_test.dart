// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_one/gg_one.dart';
import 'package:test/test.dart';

void main() {
  final messages = <String>[];
  late CommandRunner<void> runner;

  setUp(() {
    messages.clear();
    runner = CommandRunner<void>('test', 'test')
      ..addCommand(DoUpgrade(ggLog: messages.add));
  });

  group('DoUpgrade', () {
    test('has the name and description of the group', () {
      final upgrade = DoUpgrade(ggLog: messages.add);
      expect(upgrade.name, 'upgrade');
      expect(upgrade.description, 'Upgrade parts of the repository');
    });

    test('offers the dependencies subcommand', () async {
      await capturePrint(
        ggLog: messages.add,
        code: () async => await runner.run(['upgrade', '--help']),
      );

      expect(messages.join('\n'), contains('dependencies'));
    });

    test('takes the subcommands from the injected dependencies', () {
      final deps = DepsOfDoUpgrade(ggLog: messages.add);
      final upgrade = DoUpgrade(ggLog: messages.add, deps: deps);

      expect(upgrade.subcommands.keys, contains('dependencies'));
      expect(deps.dependencies.name, 'dependencies');
    });
  });
}
