// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_one/gg_one.dart';
import 'package:gg_log/gg_log.dart';
import 'package:test/test.dart';

void main() {
  final messages = <String>[];
  final GgLog ggLog = messages.add;
  final checks = Checks(ggLog: ggLog);

  group('Checks', () {
    group('all', () {
      test('should provide a list of all checks', () {
        expect(checks.all, hasLength(10));
        expect(checks.all, [
          checks.pubGetOffline,
          checks.analyze,
          checks.format,
          checks.tests,
          checks.pana,
          checks.isPushed,
          checks.isCommitted,
          checks.isVersioned,
          checks.isPublished,
          checks.isUpgraded,
        ]);
      });
    });
  });
}
