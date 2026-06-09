// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_log/gg_log.dart';
import 'package:gg_process/gg_process.dart';
import 'package:path/path.dart';

// #############################################################################
/// Creates the git tag that mirrors the `version` field of a TypeScript
/// project's `package.json`.
///
/// The Dart/Flutter publish flow uses `AddVersionTag` from `gg_version`, which
/// reconciles `pubspec.yaml`, `CHANGELOG.md`, and the latest git tag.
/// TypeScript projects don't carry a CHANGELOG-driven version, so the tag is
/// derived purely from `package.json` — that's the version `npm`/`pnpm`
/// consumers expect to resolve `#semver:<range>` against.
///
/// The tag name is the raw version string (e.g. `0.1.3`), matching the format
/// `AddVersionTag` writes for Dart so downstream tooling (and `pnpm`'s git
/// resolver) accept either project type without special-casing.
///
/// The operation is **idempotent**: if HEAD already carries the version tag,
/// the call is a no-op. Missing or unparseable `package.json` or `version`
/// fields are silent no-ops too — the caller decided this is a TS project, we
/// just have nothing to do.
class AddTypeScriptVersionTag {
  /// Constructor.
  ///
  /// [ggLog] is bound at construction time — same pattern as `AddVersionTag`
  /// in `gg_version` — so callers wire log routing once and the per-`exec`
  /// surface stays minimal.
  AddTypeScriptVersionTag({
    required this.ggLog,
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
  }) : _processWrapper = processWrapper;

  /// Receives a single human-readable status line per successful `exec`:
  /// either `Tag <v> added.` after a create or
  /// `Version <v> tag already present.` for a no-op.
  final GgLog ggLog;

  final GgProcessWrapper _processWrapper;

  // ...........................................................................
  /// Reads `<directory>/package.json` and tags HEAD with its `version`.
  ///
  /// Throws an [Exception] when `git tag` reports a non-zero exit code.
  Future<void> exec({required Directory directory}) async {
    final version = _readPackageJsonVersion(directory);
    if (version == null) return;

    if (await _headAlreadyHasTag(directory: directory, tag: version)) {
      ggLog('Version $version tag already present.');
      return;
    }

    final result = await _processWrapper.run('git', <String>[
      'tag',
      '-a',
      version,
      '-m',
      'Version $version',
    ], workingDirectory: directory.path);

    if (result.exitCode != 0) {
      throw Exception(
        'Could not add tag $version in ${directory.path}: ${result.stderr}',
      );
    }
    ggLog('Tag $version added.');
  }

  // ...........................................................................
  /// Returns the `version` field from `<directory>/package.json`, or `null`
  /// when the file is missing, unparseable, or carries no usable `version`.
  ///
  /// Kept as a small private helper rather than reaching into
  /// `gg_localize_refs.PackageJsonIo`: making `gg_one` depend on
  /// `gg_localize_refs` purely for this five-line read would invert the
  /// existing dependency direction (gg_multi → gg_one + gg_localize_refs).
  String? _readPackageJsonVersion(Directory directory) {
    final pkg = File(join(directory.path, 'package.json'));
    if (!pkg.existsSync()) return null;
    try {
      final decoded = jsonDecode(pkg.readAsStringSync());
      if (decoded is! Map) return null;
      final version = decoded['version'];
      if (version is! String || version.isEmpty) return null;
      return version;
    } catch (_) {
      return null;
    }
  }

  // ...........................................................................
  /// Whether HEAD already has a git tag named exactly [tag].
  Future<bool> _headAlreadyHasTag({
    required Directory directory,
    required String tag,
  }) async {
    final existing = await _processWrapper.run('git', <String>[
      'tag',
      '--points-at',
      'HEAD',
    ], workingDirectory: directory.path);
    return existing.stdout
        .toString()
        .split(RegExp(r'\r?\n'))
        .map((s) => s.trim())
        .contains(tag);
  }
}
