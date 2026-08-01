// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';

/// Returns an error message when [args] name a subcommand that does not exist.
///
/// The `args` package checks `--help` BEFORE it looks at the remaining
/// positional arguments (`CommandRunner.runCommand`), so `gg do xyz -h` prints
/// the usage of `do` and exits with 0 — the unknown »xyz« is swallowed. Only
/// without »-h« does it report the typo. This guard closes that hole: it walks
/// the command tree itself, before the runner sees the arguments, and reports
/// the first positional argument that should be a subcommand but is none.
///
/// Returns `null` when the arguments name no unknown subcommand — including
/// the cases the guard must not judge: a leaf command's own positional
/// arguments (`gg do create ticket 69`), everything after `--`, and option
/// values that look like a command (`gg do commit -m publish`).
String? unknownSubcommandError({
  required Command<dynamic> command,
  required List<String> args,
}) {
  var current = command;
  var commandPath = command.name;

  final tokens = [...args];

  // GgCommandRunner prepends the command name when the first non-flag argument
  // is not the name itself. Drop it here for the same reason: both spellings
  // (»gg_one do« and »do«) must walk the same tree.
  final firstNonFlag = tokens.indexWhere((a) => !a.startsWith('-'));
  if (firstNonFlag >= 0 && tokens[firstNonFlag] == command.name) {
    tokens.removeAt(firstNonFlag);
  }

  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];

    // Everything behind »--« is positional by definition.
    if (token == '--') {
      break;
    }

    if (token.startsWith('--')) {
      // »--option=value« carries its value, »--option value« consumes the next
      // token — but only when the option is not a flag.
      final name = token.substring(2).split('=').first;
      if (token.contains('=')) {
        continue;
      }

      final option =
          current.argParser.findByNameOrAlias(name) ??
          (name.startsWith('no-')
              ? current.argParser.findByNameOrAlias(name.substring(3))
              : null);

      if (option != null && !option.isFlag) {
        i++;
      }
      continue;
    }

    if (token.startsWith('-') && token.length > 1) {
      // An abbreviation cluster like »-abc«. The first abbreviation that takes
      // a value ends the cluster: the rest of the token is that value, or —
      // when the abbreviation is the last character — the next token is.
      final abbreviations = token.substring(1).split('');
      for (var c = 0; c < abbreviations.length; c++) {
        final option = current.argParser.findByAbbreviation(abbreviations[c]);
        if (option != null && !option.isFlag) {
          if (c == abbreviations.length - 1) {
            i++;
          }
          break;
        }
      }
      continue;
    }

    // A positional argument. Below a leaf command it is data, not a command.
    if (current.subcommands.isEmpty) {
      break;
    }

    final subcommand = current.subcommands[token];
    if (subcommand == null) {
      return 'Could not find a subcommand named "$token" for "$commandPath".\n'
          'Available subcommands: '
          '${(current.subcommands.keys.toList()..sort()).join(', ')}';
    }

    current = subcommand;
    commandPath = '$commandPath ${subcommand.name}';
  }

  return null;
}
