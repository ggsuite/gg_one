// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_git/gg_git.dart';
import 'package:gg_log/gg_log.dart';

// .............................................................................
/// Inform about the repo
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
  final description = 'Show information about this repo';

  // ...........................................................................
  void _initSubCommands() {
    addSubcommand(ModifiedFiles(ggLog: ggLog));
    addSubcommand(LastChangesHash(ggLog: ggLog));
  }
}
