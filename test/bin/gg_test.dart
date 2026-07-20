// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('bin/gg_one.dart', () {
    // #########################################################################

    // Spawns »dart ./bin/gg_one.dart«, which JIT-compiles the whole command
    // graph from scratch. Under the parallel test load of the full suite this
    // can exceed the 30s default, so allow more headroom to avoid a flaky
    // timeout.
    test(
      'should be executable',
      timeout: const Timeout(Duration(minutes: 3)),
      () async {
        // Execute bin/gg_one.dart and check if it prints help
        final result = await Process.run('dart', [
          './bin/gg_one.dart',
          'check',
          'analyze',
          '--help',
        ]);

        final expectedMessages = [
          RegExp(r'Usage:\s+gg_one check analyze \[arguments\]'),
        ];

        final stdout = result.stdout as String;

        for (final msg in expectedMessages) {
          expect(stdout, contains(msg));
        }
      },
    );
  });
}
