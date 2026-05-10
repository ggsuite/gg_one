// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_one/src/tools/formatter.dart';
import 'package:gg_one/src/tools/project_type.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_log/gg_log.dart';
import 'package:mocktail/mocktail.dart' as mocktail;

// #############################################################################

/// Applies formatting to the source code, dispatching to the right
/// [Formatter] based on the detected [ProjectType].
class Format extends DirCommand<void> {
  /// Constructor.
  Format({
    required super.ggLog,
    Formatter? dartFormatter,
    Formatter? typeScriptFormatter,
  }) : _dartFormatter = dartFormatter ?? const DartFormatter(),
       _typeScriptFormatter =
           typeScriptFormatter ?? const TypeScriptFormatter(),
       super(name: 'format', description: 'Runs the project formatter.');

  final Formatter _dartFormatter;
  final Formatter _typeScriptFormatter;

  // ...........................................................................
  @override
  Future<void> get({required Directory directory, required GgLog ggLog}) async {
    await check(directory: directory);

    final formatter = switch (detectProjectType(directory)) {
      ProjectType.dart || ProjectType.flutter => _dartFormatter,
      ProjectType.typescript => _typeScriptFormatter,
    };

    await formatter.run(directory: directory, ggLog: ggLog);
  }
}

// .............................................................................
/// A mocktail mock.
class MockFormat extends mocktail.Mock implements Format {}
