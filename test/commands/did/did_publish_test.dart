// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_one/src/commands/did/did_publish.dart';
import 'package:gg_one/src/tools/did_command.dart';
import 'package:gg_git/gg_git_test_helpers.dart';
import 'package:gg_log/gg_log.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

void main() {
  late Directory d;
  final messages = <String>[];
  GgLog ggLog = messages.add;
  late DidPublish didPublish;

  setUp(() async {
    messages.clear();
    d = await Directory.systemTemp.createTemp();
    if (d.existsSync()) {
      await d.delete(recursive: true);
    }
    await d.create();
    registerFallbackValue(d);

    await initGit(d);
    await addAndCommitGitIgnoreFile(d, content: '.check.json');
    await addAndCommitSampleFile(d, fileName: 'pubspec.yaml');
    didPublish = DidPublish(ggLog: messages.add);
  });

  tearDown(() async {
    await d.delete(recursive: true);
  });

  group('DidPublish', () {
    test('should work fine ', () async {
      const colorize = DidCommand.colorizeSuggestion;

      // ..................................
      // Initally the command should throw,
      // because we did not commit yet
      late String exception;
      try {
        await didPublish.exec(directory: d, ggLog: ggLog);
      } catch (e) {
        exception = e.toString();
      }
      expect(
        exception,
        contains(colorize('Not yet published. Please run »gg do publish«.')),
      );
    });
  });
}
