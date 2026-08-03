// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one/src/tools/gg_state.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:meta/meta.dart';

/// Base class for all did commands
class DidCommand extends DirCommand<bool> {
  /// Constructor
  DidCommand({
    required super.name,
    required super.description,
    required this.shortDescription,
    required this.suggestion,
    required super.ggLog,
    required this.stateKey,
    GgState? state,
  }) : state = state ?? GgState(ggLog: ggLog) {
    _addArgs();
  }

  // ...........................................................................
  @override
  @mustCallSuper
  Future<bool> exec({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    final messages = <String>[];

    final result =
        await GgStatusPrinter<bool>(
          message: shortDescription,
          ggLog: ggLog,
          dark: true,
        ).logTask(
          task: () => get(ggLog: messages.add, directory: directory),
          success: (success) => success,
        );

    if (!result) {
      // Assemble the message without colors and dim it as a whole. Coloring
      // the parts first and wrapping the result would nest escape codes into
      // each other.
      final details = messages.join('\n').trim();
      final printedMessages = <String>[
        suggestion.replaceAll('»', '').replaceAll('«', ''),
        if (details.isNotEmpty) details,
      ];

      throw Exception(cDetail(printedMessages.join('\n')));
    }

    return result;
  }

  // ...........................................................................
  /// Returns previously set value
  @override
  Future<bool> get({
    required Directory directory,
    required GgLog ggLog,
    bool? ignoreUnstaged,
  }) async {
    ignoreUnstaged ??= argResults?['ignoreUnstaged'] as bool? ?? false;

    final success = await state.readSuccess(
      directory: directory,
      key: stateKey,
      ggLog: ggLog,
      ignoreUnstaged: ignoreUnstaged,
    );

    return success;
  }

  // ...........................................................................
  /// Returns previously set value
  Future<void> set({required Directory directory}) async {
    await state.writeSuccess(directory: directory, key: stateKey);
  }

  /// The question to be answered by the did command
  final String shortDescription;

  /// The suggestions shown when the state was not successful
  final String suggestion;

  /// The state key used to retrieve the success state
  final String stateKey;

  /// Saves and restores the success state
  final GgState state;

  // ######################
  // Private
  // ######################

  // ...........................................................................
  void _addArgs() {
    argParser.addFlag(
      'ignoreUnstaged',
      abbr: 'u',
      help: 'Ignore unstaged files.',
      defaultsTo: false,
    );
  }
}

/// Mock for [DidCommand]
class MockDidCommand extends MockDirCommand<bool> implements DidCommand {}
