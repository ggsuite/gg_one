// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one/gg_one.dart';

// .............................................................................
/// Various checks for the source code
class Can extends Command<void> {
  /// Constructor
  Can({required this.ggLog, DepsOfCan? deps}) {
    deps ??= DepsOfCan(ggLog: ggLog);
    _initSubCommands(deps);
  }

  /// The log function
  final GgLog ggLog;

  /// Then name of the command
  @override
  final name = 'can';

  /// The description of the command
  @override
  final description = 'Check if you can commit, push, publish, ....';

  // ...........................................................................
  void _initSubCommands(DepsOfCan deps) {
    addSubcommand(deps.canCommit);
    addSubcommand(deps.canPush);
    addSubcommand(deps.canPublish);
    addSubcommand(deps.canUpgrade);
  }
}

// .............................................................................
/// Dependencies for the check command
class DepsOfCan {
  /// Constructor
  DepsOfCan({
    required this.ggLog,
    CanCommit? commit,
    CanPush? push,
    CanPublish? publish,
    CanUpgrade? upgrade,
  }) : canCommit = commit ?? CanCommit(ggLog: ggLog),
       canPush = push ?? CanPush(ggLog: ggLog),
       canPublish = publish ?? CanPublish(ggLog: ggLog),
       canUpgrade = upgrade ?? CanUpgrade(ggLog: ggLog);

  /// The log function
  final GgLog ggLog;

  /// The can commit command
  final CanCommit canCommit;

  /// The can push command
  final CanPush canPush;

  /// The can publish command
  final CanPublish canPublish;

  /// The can upgrade command
  final CanUpgrade canUpgrade;
}
