// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_one/gg_one.dart';
import 'package:test/test.dart';

void main() {
  group('throwWhenNotATerminal', () {
    test('throws an actionable error when stdin is not a terminal', () {
      // `dart test` runs without a terminal, so the guard must fire here —
      // exactly the headless situation it protects against.
      expect(
        () => throwWhenNotATerminal(
          'the version-increment prompt',
          'provide version_increment via .gg/.gg-publish.json',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            allOf(
              contains('stdin is not a terminal'),
              contains('the version-increment prompt'),
              contains('provide version_increment'),
            ),
          ),
        ),
      );
    });
  });
}
