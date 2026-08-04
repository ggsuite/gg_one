// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one/gg_one.dart';

/// Groups the things a repository can upgrade.
class DoUpgrade extends Command<void> {
  /// Constructor.
  DoUpgrade({required this.ggLog, DepsOfDoUpgrade? deps}) {
    deps ??= DepsOfDoUpgrade(ggLog: ggLog);
    _initSubCommands(deps);
  }

  /// The log function.
  final GgLog ggLog;

  @override
  final name = 'upgrade';

  @override
  final description = 'Upgrade parts of the repository';

  /// Adds all upgrade subcommands.
  void _initSubCommands(DepsOfDoUpgrade deps) {
    addSubcommand(deps.dependencies);
  }
}

/// Dependencies for the do upgrade command.
class DepsOfDoUpgrade {
  /// Constructor.
  DepsOfDoUpgrade({required this.ggLog, DoUpgradeDeps? dependencies})
    : dependencies = dependencies ?? DoUpgradeDeps(ggLog: ggLog);

  /// The log function.
  final GgLog ggLog;

  /// The upgrade dependencies command.
  final DoUpgradeDeps dependencies;
}
