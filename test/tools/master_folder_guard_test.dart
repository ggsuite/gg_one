// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_one/gg_one.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  // The guard looks at paths only, therefore none of these directories
  // needs to exist on disk.
  final root = Directory.systemTemp.path;

  Directory dir(List<String> segments) =>
      Directory(path.joinAll([root, ...segments]));

  group('isInMasterFolder', () {
    test('returns true for the master folder itself', () {
      expect(isInMasterFolder(dir(['.master'])), isTrue);
    });

    test('returns true for a repo inside the master folder', () {
      expect(isInMasterFolder(dir(['.master', 'ggsuite', 'gg_one'])), isTrue);
    });

    test('returns false for a repo inside a ticket workspace', () {
      expect(
        isInMasterFolder(dir(['tickets', '36_my_ticket', 'ggsuite', 'gg_one'])),
        isFalse,
      );
    });

    test('returns false for a folder only starting with ».master«', () {
      expect(isInMasterFolder(dir(['.master_backup', 'gg_one'])), isFalse);
    });
  });

  group('throwWhenInMasterFolder', () {
    test('throws an actionable error inside the master folder', () {
      expect(
        () => throwWhenInMasterFolder(dir(['.master', 'ggsuite', 'gg_one'])),
        throwsA(
          isA<Exception>().having(
            (e) => rmC(e.toString()),
            'message',
            allOf(
              // The command in yellow, file names in green, the CLI commands
              // to run next in blue.
              contains('gg do commit'),
              contains('».master«'),
              contains('gg do checkout <ticket>'),
              contains('gg do commit --force'),
            ),
          ),
        ),
      );
    });

    test('does not throw outside of the master folder', () {
      expect(
        () => throwWhenInMasterFolder(
          dir(['tickets', '36_my_ticket', 'ggsuite', 'gg_one']),
        ),
        returnsNormally,
      );
    });
  });
}
