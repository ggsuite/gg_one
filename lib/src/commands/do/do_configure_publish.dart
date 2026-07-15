// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_version/gg_version.dart';
import 'package:interact/interact.dart';
import 'package:path/path.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../tools/ensure_publish_config_ignored.dart';
import '../../tools/publish_config.dart';
import '../../tools/version_selector.dart';

/// Typedef for editing the merge message interactively.
typedef EditMessage = Future<String?> Function(String initialMessage);

/// Interactively builds the `.gg/.gg-publish.json` publish configuration for
/// the current repository: version increment (patch/minor/major) plus merge
/// message. `gg do publish` runs this automatically when it is started
/// without a configuration, so every interactive decision is made up front —
/// the same file then collects the per-step publish progress and is removed
/// after a fully successful publish.
class DoConfigurePublish extends DirCommand<void> {
  /// Constructor
  DoConfigurePublish({
    required super.ggLog,
    super.name = 'configure-publish',
    super.description =
        'Interactively create the .gg/.gg-publish.json publish '
        'configuration for the current repository.',
    VersionSelector? versionSelector,
    FromPubspec? fromPubspec,
    EditMessage? editMessage,
    EnsurePublishConfigIgnored? ensureIgnored,
    // coverage:ignore-start
  }) : _versionSelector = versionSelector ?? VersionSelector(),
       _fromPubspec = fromPubspec ?? FromPubspec(ggLog: ggLog),
       _editMessage = editMessage ?? _defaultEditMessage,
       _ensureIgnored =
           ensureIgnored ?? EnsurePublishConfigIgnored(ggLog: ggLog) {
    // coverage:ignore-end
    _addArgs();
  }

  final VersionSelector _versionSelector;
  final FromPubspec _fromPubspec;
  final EditMessage _editMessage;
  final EnsurePublishConfigIgnored _ensureIgnored;

  /// Returns the `.gg/.gg-publish.json` file for [repoDir].
  static File configFileFor(Directory repoDir) =>
      File(join(repoDir.path, '.gg', '.gg-publish.json'));

  @override
  Future<void> get({required Directory directory, required GgLog ggLog}) async {
    await configure(
      directory: directory,
      ggLog: ggLog,
      mergeMessage: argResults?['message'] as String?,
    );
  }

  /// Builds the publish configuration for [directory], writes it to
  /// `<repo>/.gg/.gg-publish.json` and returns it. Before the file is
  /// written, `.gg/.gg-publish.json` is added to the repository's
  /// `.gitignore` (and that change committed) so the runtime file never
  /// shows up as an untracked file.
  ///
  /// [versionIncrement] and [mergeMessage] are presets (e.g. from `-m` or a
  /// programmatic caller): a preset value is used as-is and its prompt is
  /// skipped. A missing merge message is asked for with the `.ticket`
  /// description as the initial value; an empty answer falls back to the
  /// description and finally to `Publish <dirname>`, so it is never empty.
  Future<PublishConfig> configure({
    required Directory directory,
    required GgLog ggLog,
    String? versionIncrement,
    String? mergeMessage,
  }) async {
    await check(directory: directory);
    await _ensureIgnored.ensure(directory: directory);

    final increment =
        versionIncrement ??
        (await _versionSelector.selectIncrement(
          currentVersion: await _currentVersion(directory),
        )).name;

    var message = mergeMessage?.trim() ?? '';
    if (message.isEmpty) {
      final ticketDescription = _readTicketDescription(directory) ?? '';
      message = (await _editMessage(ticketDescription) ?? '').trim();
      if (message.isEmpty) {
        message = ticketDescription.trim();
      }
      if (message.isEmpty) {
        message = 'Publish ${basename(directory.path)}';
      }
    }

    final config = PublishConfig(
      versionIncrement: increment,
      mergeMessage: message,
    );
    final file = configFileFor(directory);
    await config.save(file: file);
    ggLog(green('Wrote publish configuration to ${file.path}'));
    return config;
  }

  /// Reads the version used as the baseline for the increment preview.
  /// Falls back to the `package.json` version (TypeScript) and finally to
  /// 0.0.0 — only the chosen increment is stored, so the baseline is
  /// preview-only.
  Future<Version> _currentVersion(Directory directory) async {
    try {
      return await _fromPubspec.fromDirectory(directory: directory);
    } catch (_) {
      try {
        final packageJson = File(join(directory.path, 'package.json'));
        final decoded = jsonDecode(packageJson.readAsStringSync());
        return Version.parse(
          (decoded as Map<String, dynamic>)['version'].toString(),
        );
      } catch (_) {
        return Version(0, 0, 0);
      }
    }
  }

  /// Reads the optional description from the `.ticket` file, used as the
  /// default merge message. Malformed or hand-edited files must not crash
  /// the configuration.
  String? _readTicketDescription(Directory directory) {
    final ticketFile = File(join(directory.path, '.ticket'));
    if (!ticketFile.existsSync()) {
      return null;
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(ticketFile.readAsStringSync());
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final description = decoded['description']?.toString().trim();
    if (description == null || description.isEmpty) {
      return null;
    }
    return description;
  }

  /// Opens an interactive editor for the merge message.
  // coverage:ignore-start
  static Future<String?> _defaultEditMessage(String initialMessage) async {
    return Input(
      prompt: 'Edit merge message',
      defaultValue: initialMessage,
      initialText: initialMessage,
    ).interact();
  }
  // coverage:ignore-end

  void _addArgs() {
    argParser.addOption(
      'message',
      abbr: 'm',
      help:
          'The merge message to write into the configuration. When given, '
          'the interactive merge-message prompt is skipped.',
    );
  }
}

/// Mock for [DoConfigurePublish].
class MockDoConfigurePublish extends MockDirCommand<void>
    implements DoConfigurePublish {}
