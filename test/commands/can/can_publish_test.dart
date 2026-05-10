// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_one/gg_one.dart';
import 'package:gg_changelog/gg_changelog.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_git/gg_git_test_helpers.dart';
import 'package:gg_publish/gg_publish.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

// .............................................................................
void main() {
  late Directory d;
  final messages = <String>[];
  final ggLog = messages.add;
  late CanPublish canPublish;

  // ...........................................................................
  late Pana pana;
  late DidCommit didCommit;
  late IsVersionPrepared isVersionPrepared;
  late HasRightFormat hasRightFormat;

  // ...........................................................................
  void mockCommands() {
    when(() => pana.exec(directory: d, ggLog: messages.add)).thenAnswer((
      _,
    ) async {
      messages.add('pana');
    });
    when(() => didCommit.exec(directory: d, ggLog: messages.add)).thenAnswer((
      _,
    ) async {
      messages.add('didCommit');
      return true;
    });
    when(
      () => isVersionPrepared.exec(directory: d, ggLog: messages.add),
    ).thenAnswer((_) async {
      messages.add('isVersionPrepared');
      return true;
    });

    when(
      () => hasRightFormat.exec(directory: d, ggLog: messages.add),
    ).thenAnswer((_) async {
      messages.add('hasRightFormat');
      return true;
    });
  }

  // ...........................................................................
  setUp(() async {
    pana = MockPana();
    didCommit = MockDidCommit();
    isVersionPrepared = MockIsVersionPrepared();
    hasRightFormat = MockHasRightFormat();

    canPublish = CanPublish(
      ggLog: ggLog,
      pana: pana,
      didCommit: didCommit,
      isVersionPrepared: isVersionPrepared,
    );
    d = Directory.systemTemp.createTempSync();
    await initGit(d);
    await addAndCommitSampleFile(d);
    await createBranch(d, 'feat_abc');

    File(
      join(d.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: test\nrepository: https://foo.com');
  });

  // ...........................................................................
  tearDown(() {
    d.deleteSync(recursive: true);
  });

  // ...........................................................................
  group('CanPublish', () {
    group('run()', () {
      test('should run the sub commands except IsVersionPrepared', () async {
        mockCommands();
        await canPublish.exec(directory: d, ggLog: ggLog);
        var count = 0;
        expect(messages[count++], yellow('Can publish?'));
        expect(messages[count++], contains('Current branch is feature branch'));
        expect(messages[count++], contains('Current branch is feature branch'));
        expect(messages[count++], contains('⌛️ CHANGELOG.md has right format'));
        expect(messages[count++], contains('✅ CHANGELOG.md has right format'));
        expect(messages[count++], 'didCommit');
        expect(messages[count++], 'pana');
      });
    });

    test('should have a code coverage of 100%', () {
      expect(CanPublish(ggLog: ggLog), isNotNull);
    });
  });
}
