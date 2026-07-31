// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:path/path.dart' as path;

/// The name of the folder holding the master checkouts of a gg workspace.
const String masterFolderName = '.master';

/// Returns true when [directory] lies inside the workspace's master folder.
///
/// The check looks at the path only — any segment named [masterFolderName]
/// makes the directory a master directory, no matter how deep it sits below
/// it (`<root>/.master/<org>/<repo>`).
bool isInMasterFolder(Directory directory) {
  final segments = path.split(path.normalize(directory.absolute.path));
  return segments.contains(masterFolderName);
}

/// Throws when [directory] lies inside the workspace's master folder.
///
/// The master workspace only mirrors the registered repositories; changes
/// belong into a ticket workspace (`<root>/tickets/<ticket>/<org>/<repo>`).
/// Callers skip the guard when »--force« is given — the message names that
/// escape hatch, so a master repo can still be fixed in place.
void throwWhenInMasterFolder(Directory directory) {
  if (!isInMasterFolder(directory)) {
    return;
  }

  // Colors follow gg's scheme: the command in yellow, file names in green,
  // and the CLI commands to run next in blue.
  throw Exception(
    '${red('Cannot run ')}'
    '${yellow('gg do commit')}'
    '${red(' inside the ')}'
    '${green('»$masterFolderName«')}'
    '${red(' folder.\n')}'
    '${red('Switch to a ticket workspace, e.g. ')}'
    '${blue('gg do checkout <ticket>')}'
    '${red('\nOr commit anyway using ')}'
    '${blue('gg do commit --force')}',
  );
}
