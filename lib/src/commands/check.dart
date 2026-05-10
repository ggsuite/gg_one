// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_one/gg_one.dart';
import 'package:gg_log/gg_log.dart';

// .............................................................................
/// Various checks for the source code
class Check extends Command<void> {
  /// Constructor
  Check({required this.ggLog, Checks? checks}) {
    _initSubCommands(checks);
  }

  /// The log function
  final GgLog ggLog;

  /// Then name of the command
  @override
  final name = 'check';

  /// The description of the command
  @override
  final description = 'Various commands for checking the source code.';

  // ...........................................................................
  void _initSubCommands(Checks? checks) {
    checks = checks ?? Checks(ggLog: ggLog);
    for (final check in checks.all) {
      addSubcommand(check);
    }
  }
}
