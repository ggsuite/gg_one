// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_publish/gg_publish.dart' show VersionIncrement;
import 'package:path/path.dart' as p;

/// Allowed values for `version_increment` in a `.gg-publish.json` file.
const Set<String> allowedVersionIncrements = {'patch', 'minor', 'major'};

/// Returned by [PublishConfig.forRepo] (and used directly in single-repo
/// scenarios). Both fields are present and validated when this is constructed
/// — the caller may treat them as authoritative inputs to a publish run.
class ResolvedPublishValues {
  /// Creates a resolved set of publish values.
  const ResolvedPublishValues({
    required this.versionIncrement,
    required this.mergeMessage,
  });

  /// One of `patch`, `minor`, `major`.
  final String versionIncrement;

  /// The merge commit message used for the final merge step.
  final String mergeMessage;
}

/// In-memory representation of a `.gg-publish.json` config file as used by
/// `gg one do publish --config <path>` (single-repo) and
/// `gg multi do publish --config <path>` (ticket).
///
/// Schema:
/// ```json
/// {
///   "version_increment": "patch",
///   "merge_message": "Default merge message for all repos",
///   "repos": {
///     "<repoName>": {
///       "version_increment": "minor",
///       "merge_message": "Per-repo merge message"
///     }
///   }
/// }
/// ```
///
/// Top-level `version_increment` / `merge_message` are defaults. Entries
/// under `repos.<name>` override the defaults for that repo.
class PublishConfig {
  /// Constructor (used by [load] and tests).
  PublishConfig({
    this.versionIncrement,
    this.mergeMessage,
    Map<String, RepoOverride>? repos,
  }) : repos = repos ?? const {};

  /// Default `version_increment`. May be null when only per-repo overrides
  /// are specified.
  final String? versionIncrement;

  /// Default `merge_message`. May be null when only per-repo overrides are
  /// specified.
  final String? mergeMessage;

  /// Per-repo overrides keyed by repository name.
  final Map<String, RepoOverride> repos;

  /// Resolves the effective publish values for a single-repo run. Throws a
  /// [FormatException] when `version_increment` or `merge_message` is missing
  /// at the top level.
  ResolvedPublishValues resolveSingle({required String configPath}) {
    final increment = versionIncrement;
    final message = mergeMessage;
    final missing = <String>[];
    if (increment == null) missing.add('version_increment');
    if (message == null) missing.add('merge_message');
    if (missing.isNotEmpty) {
      throw FormatException(
        'Config $configPath is missing required field(s): '
        '${missing.join(", ")}',
      );
    }
    return ResolvedPublishValues(
      versionIncrement: increment!,
      mergeMessage: message!,
    );
  }

  /// Resolves the effective publish values for [repoName] in a multi-repo run.
  /// Per-repo overrides take precedence over top-level defaults. Throws a
  /// [FormatException] when neither source supplies a value for either field.
  ResolvedPublishValues forRepo({
    required String repoName,
    required String configPath,
  }) {
    final override = repos[repoName];
    final increment = override?.versionIncrement ?? versionIncrement;
    final message = override?.mergeMessage ?? mergeMessage;
    final missing = <String>[];
    if (increment == null) missing.add('version_increment');
    if (message == null) missing.add('merge_message');
    if (missing.isNotEmpty) {
      throw FormatException(
        'Config $configPath is missing required field(s) for $repoName: '
        '${missing.join(", ")} (neither top-level nor repos.$repoName).',
      );
    }
    return ResolvedPublishValues(
      versionIncrement: increment!,
      mergeMessage: message!,
    );
  }

  /// Loads a [PublishConfig] from [configArg].
  ///
  /// Resolution order:
  ///   1. [configArg] interpreted as-given (absolute or relative to CWD).
  ///   2. `<fallbackDir>/<configArg>` — for single-repo this is the repo's
  ///      `.gg/` directory; for multi-repo this is the ticket directory.
  ///
  /// Throws a [FileSystemException] when no file can be found and a
  /// [FormatException] when the file content is not a valid JSON object or
  /// when a field has an unexpected type / value.
  factory PublishConfig.load({
    required String configArg,
    required String fallbackDir,
  }) {
    final candidates = <String>[
      configArg,
      p.join(fallbackDir, configArg),
    ];
    File? found;
    for (final candidate in candidates) {
      final file = File(candidate);
      if (file.existsSync()) {
        found = file;
        break;
      }
    }
    if (found == null) {
      throw FileSystemException(
        'Could not find publish config. Tried: '
        '${candidates.join(", ")}',
        configArg,
      );
    }

    final raw = found.readAsStringSync();
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      throw FormatException(
        'Publish config ${found.path} is not valid JSON: ${e.message}',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw FormatException(
        'Publish config ${found.path} must contain a JSON object at the '
        'top level.',
      );
    }

    final increment = _readIncrement(
      decoded,
      key: 'version_increment',
      where: found.path,
    );
    final message = _readString(
      decoded,
      key: 'merge_message',
      where: found.path,
    );

    final repos = <String, RepoOverride>{};
    final rawRepos = decoded['repos'];
    if (rawRepos != null) {
      if (rawRepos is! Map<String, dynamic>) {
        throw FormatException(
          'Publish config ${found.path}: "repos" must be a JSON object.',
        );
      }
      for (final entry in rawRepos.entries) {
        final repoName = entry.key;
        final inner = entry.value;
        if (inner is! Map<String, dynamic>) {
          throw FormatException(
            'Publish config ${found.path}: repos.$repoName must be a JSON '
            'object.',
          );
        }
        repos[repoName] = RepoOverride(
          versionIncrement: _readIncrement(
            inner,
            key: 'version_increment',
            where: '${found.path} repos.$repoName',
          ),
          mergeMessage: _readString(
            inner,
            key: 'merge_message',
            where: '${found.path} repos.$repoName',
          ),
        );
      }
    }

    return PublishConfig(
      versionIncrement: increment,
      mergeMessage: message,
      repos: repos,
    );
  }

  static String? _readString(
    Map<String, dynamic> json, {
    required String key,
    required String where,
  }) {
    final v = json[key];
    if (v == null) return null;
    if (v is! String) {
      throw FormatException('$where: "$key" must be a string.');
    }
    if (v.isEmpty) {
      throw FormatException('$where: "$key" must not be empty.');
    }
    return v;
  }

  static String? _readIncrement(
    Map<String, dynamic> json, {
    required String key,
    required String where,
  }) {
    final v = _readString(json, key: key, where: where);
    if (v == null) return null;
    if (!allowedVersionIncrements.contains(v)) {
      throw FormatException(
        '$where: "$key" must be one of '
        '${allowedVersionIncrements.join(", ")} (was "$v").',
      );
    }
    return v;
  }
}

/// Per-repo override block within a [PublishConfig]. Either field may be
/// null, in which case the top-level default applies.
class RepoOverride {
  /// Constructor.
  RepoOverride({this.versionIncrement, this.mergeMessage});

  /// Per-repo `version_increment`, or null to inherit the top-level value.
  final String? versionIncrement;

  /// Per-repo `merge_message`, or null to inherit the top-level value.
  final String? mergeMessage;
}

/// Maps the string form of a version increment (as produced by
/// [PublishConfig]) to the corresponding [VersionIncrement] enum value.
/// Throws [ArgumentError] for unknown strings — callers should have validated
/// earlier via [allowedVersionIncrements].
VersionIncrement parseVersionIncrement(String increment) {
  switch (increment) {
    case 'patch':
      return VersionIncrement.patch;
    case 'minor':
      return VersionIncrement.minor;
    case 'major':
      return VersionIncrement.major;
  }
  throw ArgumentError.value(increment, 'increment', 'unknown increment');
}
