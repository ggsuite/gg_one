// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_one/gg_one.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_git/gg_git.dart' as gg_git;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _FakeDirectory extends Fake implements Directory {}

class MockFetch extends Mock implements gg_git.Fetch {}

class MockCheckout extends Mock implements gg_git.Checkout {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeDirectory());
  });

  late Directory d;
  final messages = <String>[];
  final ggLog = messages.add;
  late MockFetch fetch;
  late MockCheckout checkout;
  late DoCheckout doCheckout;
  late CommandRunner<void> runner;

  setUp(() async {
    messages.clear();
    d = await Directory.systemTemp.createTemp();
    fetch = MockFetch();
    checkout = MockCheckout();
    when(
      () => fetch.get(
        directory: any(named: 'directory'),
        ggLog: any(named: 'ggLog'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => checkout.get(
        directory: any(named: 'directory'),
        ggLog: any(named: 'ggLog'),
        branch: any(named: 'branch'),
      ),
    ).thenAnswer((_) async {});
    doCheckout = DoCheckout(ggLog: ggLog, fetch: fetch, checkout: checkout);
    runner = CommandRunner<void>('gg', 'gg')..addCommand(doCheckout);
  });

  tearDown(() async {
    await d.delete(recursive: true);
  });

  group('DoCheckout', () {
    test('initializes with defaults', () {
      final instance = DoCheckout(ggLog: ggLog);
      expect(instance.name, 'checkout');
      expect(
        instance.description,
        'Check out the branch belonging to a ticket.',
      );
    });

    test('fetches then checks out the branch', () async {
      await doCheckout.get(directory: d, ggLog: ggLog, branch: 'my-branch');

      verifyInOrder([
        () => fetch.get(directory: d, ggLog: ggLog),
        () => checkout.get(directory: d, ggLog: ggLog, branch: 'my-branch'),
      ]);
      expect(messages.last, green('Checked out my-branch.'));
    });

    test('reads the branch name from the positional argument', () async {
      await runner.run(['checkout', '-i', d.path, 'feat_cli']);

      verify(
        () => checkout.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          branch: 'feat_cli',
        ),
      ).called(1);
    });

    test('throws a usage exception when no name is given', () async {
      await expectLater(
        runner.run(['checkout', '-i', d.path]),
        throwsA(isA<UsageException>()),
      );

      verifyNever(
        () => fetch.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      );
    });

    group('exec', () {
      test('delegates to get', () async {
        await doCheckout.exec(directory: d, ggLog: ggLog, branch: 'b');

        verify(
          () => checkout.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            branch: 'b',
          ),
        ).called(1);
      });
    });
  });
}
