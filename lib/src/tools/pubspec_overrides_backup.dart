// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:path/path.dart';

import '../commands/check/no_pubspec_overrides.dart';

/// Where a publish keeps the `pubspec_overrides.yaml` it has to delete.
///
/// The file lives inside `.gg/`, which is gitignored (`.gg/*`), so the backup
/// never reaches a release, a merge or the working-tree hash — while the
/// overrides file itself is tracked, because it travels with shared ticket
/// workspaces.
const String pubspecOverridesBackupPath = '.gg/pubspec_overrides_backup.yaml';

/// Saves `pubspec_overrides.yaml` of [directory] to
/// [pubspecOverridesBackupPath] so it can be restored after the publish.
///
/// Publishing deletes the overrides file — the package must resolve against
/// the registry, not against the developer's working copies. Without a backup
/// the repository loses its workspace wiring the moment it is published;
/// with it, the multi-repo flow puts the file back once the merge into the
/// main branch is through, so the repo stays workable.
///
/// An existing backup is overwritten — the current overrides are the truth.
/// Returns whether a backup was written; without an overrides file there is
/// nothing to save and the previous backup (if any) stays untouched.
bool backupPubspecOverrides(Directory directory) {
  final overrides = File(join(directory.path, NoPubspecOverrides.fileName));
  if (!overrides.existsSync()) {
    return false;
  }

  final backup = File(join(directory.path, pubspecOverridesBackupPath));
  backup.parent.createSync(recursive: true);
  overrides.copySync(backup.path);
  return true;
}

/// Restores `pubspec_overrides.yaml` of [directory] from
/// [pubspecOverridesBackupPath] and deletes the backup.
///
/// The counterpart of [backupPubspecOverrides]: once the published state is
/// merged into the main branch and the feature branch is checked out again,
/// the overrides return and the repository resolves its dependencies against
/// the sibling checkouts of the ticket like before the publish.
///
/// An overrides file that already exists is overwritten — the backup holds
/// the pre-publish truth. Returns whether a backup was restored.
bool restorePubspecOverrides(Directory directory) {
  final backup = File(join(directory.path, pubspecOverridesBackupPath));
  if (!backup.existsSync()) {
    return false;
  }

  final overrides = File(join(directory.path, NoPubspecOverrides.fileName));
  backup.copySync(overrides.path);
  backup.deleteSync();
  return true;
}
