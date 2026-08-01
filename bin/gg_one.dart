#!/usr/bin/env dart
// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_one/gg_one.dart';

import 'package:gg_log/gg_log.dart';
import 'package:gg_process/gg_process.dart';

// .............................................................................
Future<void> run({
  required List<String> args,
  required GgLog ggLog,
  GgProcessWrapper processWrapper = const GgProcessWrapper(),
}) async {
  final command = Gg(ggLog: ggLog, processWrapper: processWrapper);

  // »args« checks --help before the remaining arguments, so an unknown
  // subcommand combined with »-h« would silently print a usage text instead of
  // failing. Report it here, before the runner sees the arguments.
  final error = unknownSubcommandError(command: command, args: args);
  if (error != null) {
    ggLog(red(error));
    exitCode = 1;
    return;
  }

  await GgCommandRunner(ggLog: ggLog, command: command).run(args: args);
}

// .............................................................................
Future<void> main(List<String> args) async {
  await run(args: args, ggLog: print, processWrapper: const GgProcessWrapper());
}
