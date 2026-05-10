// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_one/src/tools/gg_state.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
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
        ).logTask(
          task: () => get(ggLog: messages.add, directory: directory),
          success: (success) => success,
        );

    if (!result) {
      final printedMessages = <String>[
        colorizeSuggestion(suggestion),
        brightBlack(messages.join('\n')),
      ];

      throw Exception(printedMessages.join('\n'));
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

  /// Formats the suggestion string by applying the blue color to the text
  /// between » and «
  static String colorizeSuggestion(String suggestion) {
    const startSymbol = '»';
    const endSymbol = '«';

    StringBuffer buffer = StringBuffer();
    int startIndex = 0;
    int endIndex = 0;

    // Loop through the input string to find and process all occurrences
    while (true) {
      startIndex = suggestion.indexOf(startSymbol, endIndex);
      if (startIndex == -1) break; // No more start symbols found, exit loop

      // Add text up to the startSymbol to the buffer
      buffer.write(darkGray(suggestion.substring(endIndex, startIndex)));

      endIndex = suggestion.indexOf(endSymbol, startIndex);
      if (endIndex == -1) break; // No matching end symbol found, exit loop

      // Extract the text between the symbols, apply the format function,
      // and add to the buffer
      String textToFormat = suggestion.substring(startIndex + 1, endIndex);
      buffer.write(blue(textToFormat));

      endIndex += 1; // Move past the endSymbol for the next iteration
    }

    // Add any remaining text after the last processed section
    buffer.write(darkGray(suggestion.substring(endIndex)));

    return buffer.toString();
  }

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
