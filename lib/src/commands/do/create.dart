// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_one/gg_one.dart';
import 'package:gg_log/gg_log.dart';

/// Groups commands for creating new development artifacts.
class Create extends Command<void> {
  /// Constructor.
  Create({required this.ggLog, DepsOfCreate? deps}) {
    deps ??= DepsOfCreate(ggLog: ggLog);
    _initSubCommands(deps);
  }

  /// The log function.
  final GgLog ggLog;

  @override
  final name = 'create';

  @override
  final description = 'Create development artifacts like ticket branches.';

  /// Adds all create subcommands.
  void _initSubCommands(DepsOfCreate deps) {
    addSubcommand(deps.createTicket);
  }
}

/// Dependencies for the create command.
class DepsOfCreate {
  /// Constructor.
  DepsOfCreate({required this.ggLog, CreateTicket? createTicket})
    : createTicket = createTicket ?? CreateTicket(ggLog: ggLog);

  /// The log function.
  final GgLog ggLog;

  /// The ticket creation command.
  final CreateTicket createTicket;
}
