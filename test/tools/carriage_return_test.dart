// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_one/src/tools/carriage_return.dart';
import 'package:test/test.dart';

void main() {
  group('carriageReturn', () {
    test('should have the right value', () {
      // const CarriageReturn();
      expect(carriageReturn, '\x1b[1A\x1b[2K');
    });
  });
}
