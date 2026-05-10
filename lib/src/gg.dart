// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_one/gg_one.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_process/gg_process.dart';

/// The command line interface for gg_one
class Gg extends Command<dynamic> {
  /// Constructor
  Gg({
    required this.ggLog,
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
  }) {
    addSubcommand(Check(ggLog: ggLog));
    addSubcommand(Can(ggLog: ggLog));
    addSubcommand(Did(ggLog: ggLog));
    addSubcommand(Do(ggLog: ggLog));
    addSubcommand(Info(ggLog: ggLog));
  }

  /// The log function
  final GgLog ggLog;

  // ...........................................................................
  @override
  final name = 'gg_one';
  @override
  final description = 'The convenient dart & flutter developer commandline.';
}
