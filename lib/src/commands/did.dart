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
class Did extends Command<void> {
  /// Constructor
  Did({required this.ggLog, DepsOfDid? deps}) {
    deps ??= DepsOfDid(ggLog: ggLog);
    _initSubCommands(deps);
  }

  /// The log function
  final GgLog ggLog;

  /// Then name of the command
  @override
  final name = 'did';

  /// The description of the command
  @override
  final description = 'Checks if you did commit, push, publish, ....';

  // ...........................................................................
  void _initSubCommands(DepsOfDid deps) {
    addSubcommand(deps.didCommit);
    addSubcommand(deps.didPush);
    addSubcommand(deps.didPublish);
    addSubcommand(deps.didUpgrade);
    addSubcommand(deps.didMerge);
  }
}

// .............................................................................
/// Dependencies for the check command
class DepsOfDid {
  /// Constructor
  DepsOfDid({
    required this.ggLog,
    DidCommit? commit,
    DidPush? push,
    DidPublish? publish,
    DidUpgrade? upgrade,
    DidMerge? merge,
  }) : didCommit = commit ?? DidCommit(ggLog: ggLog),
       didPush = push ?? DidPush(ggLog: ggLog),
       didPublish = publish ?? DidPublish(ggLog: ggLog),
       didUpgrade = upgrade ?? DidUpgrade(ggLog: ggLog),
       didMerge = merge ?? DidMerge(ggLog: ggLog);

  /// The log function
  final GgLog ggLog;

  /// The can commit command
  final DidCommit didCommit;

  /// The can push command
  final DidPush didPush;

  /// The can publish command
  final DidPublish didPublish;

  /// The can publish command
  final DidUpgrade didUpgrade;

  /// The did merge command
  final DidMerge didMerge;
}
