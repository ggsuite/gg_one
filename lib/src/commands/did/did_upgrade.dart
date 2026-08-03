// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_one/gg_one.dart';
import 'package:gg_log/gg_log.dart';

/// Groups the things whose upgrade can be checked.
class DidUpgrade extends Command<void> {
  /// Constructor.
  DidUpgrade({required this.ggLog, DepsOfDidUpgrade? deps}) {
    deps ??= DepsOfDidUpgrade(ggLog: ggLog);
    _initSubCommands(deps);
  }

  /// The log function.
  final GgLog ggLog;

  @override
  final name = 'upgrade';

  @override
  final description = 'Check what was already upgraded';

  /// Adds all upgrade subcommands.
  void _initSubCommands(DepsOfDidUpgrade deps) {
    addSubcommand(deps.dependencies);
  }
}

/// Dependencies for the did upgrade command.
class DepsOfDidUpgrade {
  /// Constructor.
  DepsOfDidUpgrade({required this.ggLog, DidUpgradeDependencies? dependencies})
    : dependencies = dependencies ?? DidUpgradeDependencies(ggLog: ggLog);

  /// The log function.
  final GgLog ggLog;

  /// The did upgrade dependencies command.
  final DidUpgradeDependencies dependencies;
}
