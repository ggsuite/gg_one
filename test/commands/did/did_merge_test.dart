// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_one/gg_one.dart';
import 'package:gg_git/gg_git_test_helpers.dart';
import 'package:test/test.dart';

void main() {
  late Directory d;
  final messages = <String>[];
  final ggLog = messages.add;
  late DidMerge didMerge;

  setUp(() async {
    messages.clear();
    d = await Directory.systemTemp.createTemp();
    await initGit(d);
    await addAndCommitSampleFile(d);
    didMerge = DidMerge(ggLog: ggLog);
  });

  tearDown(() async {
    await d.delete(recursive: true);
  });

  group('DidMerge', () {
    test('should return false initially', () async {
      final result = await didMerge.get(directory: d, ggLog: ggLog);
      expect(result, isFalse);
    });

    test('should return true after set', () async {
      await didMerge.set(directory: d);
      final result = await didMerge.get(directory: d, ggLog: ggLog);
      expect(result, isTrue);
    });

    test('should throw with suggestion when not merged', () async {
      expect(() => didMerge.exec(directory: d, ggLog: ggLog), throwsException);
    });
  });
}
