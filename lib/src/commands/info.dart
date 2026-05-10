// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_git/gg_git.dart';
import 'package:gg_log/gg_log.dart';

// .............................................................................
/// Commands to inform about the source code
class Info extends Command<void> {
  /// Constructor
  Info({required this.ggLog}) {
    _initSubCommands();
  }

  /// The log function
  final GgLog ggLog;

  /// Then name of the command
  @override
  final name = 'info';

  /// The description of the command
  @override
  final description = 'Commands to inform about the source code.';

  // ...........................................................................
  void _initSubCommands() {
    addSubcommand(ModifiedFiles(ggLog: ggLog));
    addSubcommand(LastChangesHash(ggLog: ggLog));
  }
}
