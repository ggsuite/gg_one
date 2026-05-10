// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_one/gg_one.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_git/gg_git_test_helpers.dart';
import 'package:gg_publish/gg_publish.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

void main() {
  late Directory d;
  final messages = <String>[];
  final ggLog = messages.add;
  late CanCheckout canCheckout;
  late MockIsMainBranch isMainBranch;

  setUp(() async {
    registerFallbackValue(Directory(''));
    messages.clear();
    d = await Directory.systemTemp.createTemp();
    await initGit(d);
    await addAndCommitSampleFile(d);
    isMainBranch = MockIsMainBranch();
    when(
      () => isMainBranch.exec(directory: d, ggLog: ggLog),
    ).thenAnswer((_) async => true);
    canCheckout = CanCheckout(ggLog: ggLog, isMainBranch: isMainBranch);
  });

  tearDown(() async {
    await d.delete(recursive: true);
  });

  group('CanCheckout', () {
    group('constructor', () {
      test('should initialize with defaults', () {
        final instance = CanCheckout(ggLog: ggLog);
        expect(instance.name, 'checkout');
        expect(
          instance.description,
          'Are the current changes ready for a new checkout?',
        );
        expect(instance.shortDescription, 'Can checkout?');
        expect(instance.stateKey, 'canCheckout');
        expect(instance.commands.length, 1);
        expect(instance.commands[0], isA<IsMainBranch>());
      });
    });

    test('should run IsMainBranch', () async {
      await canCheckout.exec(directory: d, ggLog: ggLog);

      expect(messages.first, yellow('Can checkout?'));
      verify(() => isMainBranch.exec(directory: d, ggLog: ggLog)).called(1);
    });
  });
}
