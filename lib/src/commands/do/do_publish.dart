// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_one/gg_one.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_changelog/gg_changelog.dart' as changelog;
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_git/gg_git.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_process/gg_process.dart';
import 'package:gg_publish/gg_publish.dart';
import 'package:gg_version/gg_version.dart';
import 'package:interact/interact.dart';
import 'package:path/path.dart';
import 'package:pub_semver/pub_semver.dart';

/// Typedef for confirming feature branch deletion.
typedef ConfirmDeleteFeatureBranch = bool Function(String branchName);

/// Typedef for editing the merge message interactively.
typedef EditMessage = Future<String?> Function(String initialMessage);

/// Publishes the current directory.
class DoPublish extends DirCommand<void> {
  /// Constructor
  DoPublish({
    required super.ggLog,
    super.name = 'publish',
    super.description = 'Publishes the current directory.',
    CanPublish? canPublish,
    Publish? publish,
    GgState? state,
    AddVersionTag? addVersionTag,
    AddTypeScriptVersionTag? addTypeScriptVersionTag,
    Commit? commit,
    DoPush? doPush,
    PrepareNextVersion? prepareNextVersion,
    FromPubspec? fromPubspec,
    IsPublished? isPublished,
    changelog.Release? release,
    PublishTo? publishTo,
    DoMerge? doMerge,
    VersionSelector? versionSelector,
    PublishedVersion? publishedVersion,
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
    LocalBranch? localBranch,
    ConfirmDeleteFeatureBranch? confirmDeleteFeatureBranch,
    EditMessage? editMessage,
    // coverage:ignore-start
  }) : _canPublish = canPublish ?? CanPublish(ggLog: ggLog),
       _publishToPubDev = publish ?? Publish(ggLog: ggLog),
       _state = state ?? GgState(ggLog: ggLog),
       _addVersionTag = addVersionTag ?? AddVersionTag(ggLog: ggLog),
       _addTypeScriptVersionTag =
           addTypeScriptVersionTag ??
           AddTypeScriptVersionTag(
             ggLog: (msg) => ggLog('✅ $msg'),
             processWrapper: processWrapper,
           ),
       _commit = commit ?? Commit(ggLog: ggLog),
       _doPush = doPush ?? DoPush(ggLog: ggLog),
       _prepareNextVersion =
           prepareNextVersion ?? PrepareNextVersion(ggLog: ggLog),
       _fromPubspec = fromPubspec ?? FromPubspec(ggLog: ggLog),
       _releaseChangelog = release ?? changelog.Release(ggLog: ggLog),
       _isPublished = isPublished ?? IsPublished(ggLog: ggLog),
       _publishTo = publishTo ?? PublishTo(ggLog: ggLog),
       _doMerge = doMerge ?? DoMerge(ggLog: ggLog),
       _versionSelector = versionSelector ?? VersionSelector(),
       _publishedVersion = publishedVersion,
       _processWrapper = processWrapper,
       _localBranch = localBranch ?? LocalBranch(ggLog: ggLog),
       _confirmDeleteFeatureBranch =
           confirmDeleteFeatureBranch ?? _defaultConfirmDeleteFeatureBranch,
       _editMessage = editMessage ?? _defaultEditMessage {
    // coverage:ignore-end
    _addArgs();
  }

  /// The key used to save the state of the command.
  final String stateKey = 'doPublish';

  /// The key used to save the prepared version state.
  final String stateKeyDoPrepareVersion = 'doPrepareVersion';

  /// The key used to save the pub.dev publishing state.
  final String stateKeyDoPublishPubDev = 'doPublishPubDev';

  /// The key used to save the merge state.
  final String stateKeyDoMerge = 'doMerge';

  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
    bool? askBeforePublishing,
    String? message,
    bool? deleteFeatureBranch,
    bool? verbose,
    String? versionIncrement,
  }) => get(
    directory: directory,
    ggLog: ggLog,
    askBeforePublishing: askBeforePublishing,
    message: message,
    deleteFeatureBranch: deleteFeatureBranch,
    verbose: verbose,
    versionIncrement: versionIncrement,
  );

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    bool? askBeforePublishing,
    String? message,
    bool? deleteFeatureBranch,
    bool? verbose,
    String? versionIncrement,
  }) async {
    final isVerbose = verbose ?? _verboseFromArgs;
    _publishedVersion ??= PublishedVersion(ggLog: ggLog);

    // Load --config <path> (with .gg/ fallback) for version_increment + msg.
    if (versionIncrement == null || message == null) {
      final configArg = argResults?['config'] as String?;
      if (configArg != null) {
        final config = PublishConfig.load(
          configArg: configArg,
          fallbackDir: join(directory.path, '.gg'),
        );
        final resolved = config.resolveSingle(configPath: configArg);
        versionIncrement ??= resolved.versionIncrement;
        message ??= resolved.mergeMessage;
      }
    }

    _explicitVersionIncrement = versionIncrement;

    message = await _resolveMergeMessage(
      directory: directory,
      message: message,
    );

    // Does directory exist?
    await check(directory: directory);
    void noLog(_) {} // coverage:ignore-line

    final branchName = await _localBranch.get(
      directory: directory,
      ggLog: <String>[].add,
    );

    // Did already publish?
    final isDone = await _state.readSuccess(
      directory: directory,
      key: stateKey,
      ggLog: ggLog,
    );

    if (isDone) {
      ggLog(yellow('Current state is already published.'));
      return;
    }

    // Can publish?
    await _canPublish.exec(directory: directory, ggLog: ggLog);

    await _doPush.gitPush(directory: directory, force: false);

    final didPrepareVersion = await _state.readSuccess(
      directory: directory,
      key: stateKeyDoPublishPubDev,
      ggLog: ggLog,
    );

    if (!didPrepareVersion) {
      await _prepareVersion(directory: directory, ggLog: ggLog, noLog: noLog);

      await _state.writeSuccess(
        directory: directory,
        key: stateKeyDoPrepareVersion,
      );
    }

    final didPublishPubDev = await _didPublishPubDevOrVersionAlreadyPublished(
      directory: directory,
      ggLog: ggLog,
    );

    if (!didPublishPubDev) {
      final hashBeforePubDev = await _state.currentHash(
        directory: directory,
        ggLog: ggLog,
      );

      await _publishToPubDevIfNeeded(
        directory: directory,
        ggLog: ggLog,
        askBeforePublishing: askBeforePublishing,
      );

      await _commitLockFileIfChanged(
        directory: directory,
        ggLog: ggLog,
        hashBefore: hashBeforePubDev,
        verbose: isVerbose,
      );

      await _state.writeSuccess(
        directory: directory,
        key: stateKeyDoPublishPubDev,
      );
    }

    final didMerge = await _state.readSuccess(
      directory: directory,
      key: stateKeyDoMerge,
      ggLog: ggLog,
    );

    if (!didMerge) {
      await _merge(directory: directory, message: message, verbose: isVerbose);

      await _state.writeSuccess(directory: directory, key: stateKeyDoMerge);
    }

    // Save state
    await _state.writeSuccess(directory: directory, key: stateKey);

    await _doPush.gitPush(directory: directory, force: false);

    final shouldDelete = await _resolveDeleteFeatureBranch(
      branchName: branchName,
      deleteFeatureBranch: deleteFeatureBranch,
    );

    if (shouldDelete) {
      await _deleteFeatureBranch(
        directory: directory,
        branchName: branchName,
        verbose: isVerbose,
      );
    }

    await _publishGit(directory: directory, ggLog: ggLog);
    await _doPush.gitPush(directory: directory, force: false, pushTags: true);
  }

  final Publish _publishToPubDev;
  final CanPublish _canPublish;
  final GgState _state;
  final AddVersionTag _addVersionTag;
  final AddTypeScriptVersionTag _addTypeScriptVersionTag;
  final DoPush _doPush;
  final Commit _commit;
  final PrepareNextVersion _prepareNextVersion;
  final FromPubspec _fromPubspec;
  final changelog.Release _releaseChangelog;
  final IsPublished _isPublished;
  final PublishTo _publishTo;
  final DoMerge _doMerge;
  final VersionSelector _versionSelector;
  PublishedVersion? _publishedVersion;
  final GgProcessWrapper _processWrapper;
  final LocalBranch _localBranch;
  final ConfirmDeleteFeatureBranch _confirmDeleteFeatureBranch;
  final EditMessage _editMessage;

  /// Pre-resolved version increment; when set, skips the interactive prompt.
  String? _explicitVersionIncrement;

  /// Returns true when pub.dev publishing was already completed or is obsolete.
  Future<bool> _didPublishPubDevOrVersionAlreadyPublished({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    final didPublishPubDev = await _state.readSuccess(
      directory: directory,
      key: stateKeyDoPublishPubDev,
      ggLog: ggLog,
    );

    if (didPublishPubDev) {
      return true;
    }

    final currentVersion = await _fromPubspec.get(
      directory: directory,
      ggLog: <String>[].add,
    );
    try {
      final publishedVersion = await _publishedVersion!.get(
        directory: directory,
        ggLog: <String>[].add,
      );

      return currentVersion == publishedVersion;
      // coverage:ignore-start
    } catch (e) {
      ggLog(yellow('$e'));
      ggLog(yellow('Assuming that the package is not published on pub.dev'));

      return false;
    }
    // coverage:ignore-end
  }

  /// Prepare the next version and release the changelog.
  Future<void> _prepareVersion({
    required Directory directory,
    required GgLog ggLog,
    required GgLog noLog,
  }) async {
    await _addNextVersion(directory, ggLog);

    // CHANGELOG.md release is Dart/Flutter only; TS uses manifest versioning.
    if (_supportsChangeLog(directory)) {
      await _prepareChangelog(directory: directory, ggLog: noLog);
    }
  }

  /// Publish to the package registry when the package should be published.
  Future<void> _publishToPubDevIfNeeded({
    required Directory directory,
    required GgLog ggLog,
    required bool? askBeforePublishing,
  }) async {
    final publishToRegistry = await _shouldPublishToRegistry(directory, ggLog);

    if (!publishToRegistry) {
      return;
    }

    final shouldAskBeforePublishing = await _shouldAskBeforePublishing(
      directory,
      ggLog,
      askBeforePublishing,
    );

    await _publishToPubDev.exec(
      directory: directory,
      ggLog: ggLog,
      askBeforePublishing: shouldAskBeforePublishing,
    );
  }

  /// Perform the local merge and push commits afterwards.
  Future<void> _merge({
    required Directory directory,
    required String? message,
    required bool verbose,
  }) async {
    await _doMerge.get(
      directory: directory,
      ggLog: verbose ? ggLog : <String>[].add,
      automerge: false,
      local: true,
      message: message,
      verbose: verbose,
    );
  }

  /// Adds the version tag for [directory] so `do_push --tags` carries it.
  /// Dart uses `AddVersionTag` (pubspec ↔ CHANGELOG); TS reads
  /// `package.json` via [AddTypeScriptVersionTag] — required for `#semver:`.
  Future<void> _publishGit({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    if (_supportsChangeLog(directory)) {
      await _addVersionTag.exec(
        directory: directory,
        ggLog: (msg) => ggLog('✅ $msg'),
      );
      return;
    }
    if (detectProjectType(directory) == ProjectType.typescript) {
      // ggLog with `✅` prefix is bound at construction time.
      await _addTypeScriptVersionTag.exec(directory: directory);
    }
  }

  /// Prepare the changelog for release and commit the result.
  Future<void> _prepareChangelog({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    final hashBefore = await _state.currentHash(
      directory: directory,
      ggLog: ggLog,
    );

    await _releaseChangelog.exec(directory: directory, ggLog: ggLog);

    await _state.updateHash(hash: hashBefore, directory: directory);

    await _commit.commit(
      ggLog: ggLog,
      directory: directory,
      doStage: true,
      message: 'Prepare changelog for release',
      ammendWhenNotPushed: true,
    );
  }

  /// Increases the version according to the selected increment.
  Future<void> _addNextVersion(Directory directory, GgLog ggLog) async {
    if (!_shouldIncreaseVersion) {
      return;
    }

    final hashBefore = await _state.currentHash(
      directory: directory,
      ggLog: ggLog,
    );

    final currentVersion = await _currentVersionForIncrementSelection(
      directory: directory,
      ggLog: ggLog,
    );

    final VersionIncrement increment;
    final explicit = _explicitVersionIncrement;
    if (explicit != null) {
      // Increment was supplied (via --config or caller); skip prompt.
      increment = parseVersionIncrement(explicit);
    } else {
      increment = await _versionSelector.selectIncrement(
        currentVersion: currentVersion,
      );
    }

    await _prepareNextVersion.exec(
      directory: directory,
      ggLog: ggLog,
      increment: increment,
      publishedVersion: currentVersion,
    );

    await _state.updateHash(hash: hashBefore, directory: directory);

    final newVersion = await _fromPubspec.fromDirectory(directory: directory);

    await _commit.commit(
      ggLog: ggLog,
      directory: directory,
      doStage: true,
      message: 'Finish development of version $newVersion',
      ammendWhenNotPushed: false,
    );
  }

  /// Resolve the version used as baseline for selecting the next increment.
  Future<Version> _currentVersionForIncrementSelection({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    final publishedVersion = await _publishedVersion!.get(
      ggLog: ggLog,
      directory: directory,
    );

    if (publishedVersion != Version(0, 0, 0)) {
      return publishedVersion;
    }

    return _fromPubspec.fromDirectory(directory: directory);
  }

  /// Returns whether publishing confirmation should be shown.
  Future<bool> _shouldAskBeforePublishing(
    Directory directory,
    GgLog ggLog,
    bool? askBeforePublishing,
  ) async {
    askBeforePublishing ??= _askBeforePublishingFromParam;

    final target = await _publishTo.fromDirectory(directory);
    final publishToNone = target == 'none';
    if (publishToNone) {
      return false;
    }

    final wasPublishedBefore = await _isPublished.get(
      directory: directory,
      ggLog: ggLog,
    );

    if (askBeforePublishing) {
      return true;
    }

    if (wasPublishedBefore) {
      return false;
    }

    throw Exception(
      'The package was never published to pub.dev before. '
      'Please call »gg do push« with »--ask-before-publishing« '
      'when publishing the first time.',
    );
  }

  /// Commits the lock file if it was modified during publishing.
  /// Lock file name is resolved per project type via the language catalog.
  Future<void> _commitLockFileIfChanged({
    required Directory directory,
    required GgLog ggLog,
    required int hashBefore,
    required bool verbose,
  }) async {
    final lockFile = lockFileFor(directory);
    final result = await _runProcess(
      'git',
      ['status', '--porcelain', lockFile],
      directory: directory,
      ggLog: ggLog,
      verbose: verbose,
    );

    if (result.stdout.toString().trim().isEmpty) {
      return;
    }

    await _state.updateHash(hash: hashBefore, directory: directory);

    await _commit.commit(
      ggLog: ggLog,
      directory: directory,
      doStage: true,
      message: 'Update $lockFile',
      ammendWhenNotPushed: true,
    );
  }

  /// Returns whether the package should be published to its registry
  /// (pub.dev for Dart/Flutter, npm for TypeScript). Uses the language-aware
  /// publish target instead of assuming a pubspec.yaml.
  Future<bool> _shouldPublishToRegistry(
    Directory directory,
    GgLog ggLog,
  ) async {
    final target = await _publishTo.fromDirectory(directory);
    return target == 'pub.dev' || target == 'npm';
  }

  /// Whether [directory] uses the Dart/Flutter CHANGELOG.md based versioning
  /// flow. TypeScript and other project types use a registry/manifest flow.
  bool _supportsChangeLog(Directory directory) =>
      detectProjectType(directory).isDartFamily;

  /// Resolves the merge message from parameters, args, or .ticket.
  Future<String?> _resolveMergeMessage({
    required Directory directory,
    required String? message,
  }) async {
    if (message != null) {
      return message;
    }

    final messageFromArgs = _messageFromArgs;
    if (messageFromArgs != null) {
      return messageFromArgs;
    }

    final initialMessage = await _readTicketDescription(directory) ?? '';
    return _editMessage(initialMessage);
  }

  /// Reads the optional description from the .ticket file.
  Future<String?> _readTicketDescription(Directory directory) async {
    final ticketFile = File(join(directory.path, '.ticket'));
    if (!await ticketFile.exists()) {
      return null;
    }

    final raw = await ticketFile.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final description = decoded['description']?.toString().trim();
    if (description == null || description.isEmpty) {
      return null;
    }

    return description;
  }

  /// Resolves whether the feature branch should be deleted after publishing.
  Future<bool> _resolveDeleteFeatureBranch({
    required String branchName,
    required bool? deleteFeatureBranch,
  }) async {
    if (deleteFeatureBranch != null) {
      return deleteFeatureBranch;
    }

    if (_deleteFeatureBranchWasProvided) {
      return _deleteFeatureBranchFromArgs;
    }

    return _confirmDeleteFeatureBranch(branchName);
  }

  /// Deletes the provided feature branch on the remote.
  Future<void> _deleteFeatureBranch({
    required Directory directory,
    required String branchName,
    required bool verbose,
  }) async {
    final result = await _runProcess(
      'git',
      <String>['push', 'origin', '--delete', branchName],
      directory: directory,
      ggLog: ggLog,
      verbose: verbose,
    );

    if (result.exitCode != 0) {
      throw Exception(
        'git push origin --delete $branchName failed: ${result.stderr}',
      );
    }

    ggLog(green('Deleted remote feature branch $branchName.'));
  }

  /// Wrapper around `_processWrapper.run` that prints the command in verbose
  /// mode.
  Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments, {
    required Directory directory,
    required GgLog ggLog,
    required bool verbose,
  }) {
    if (verbose) {
      ggLog('\$ $executable ${arguments.join(' ')}');
    }
    return _processWrapper.run(
      executable,
      arguments,
      workingDirectory: directory.path,
    );
  }

  bool get _verboseFromArgs => argResults?['verbose'] as bool? ?? false;

  bool get _askBeforePublishingFromParam =>
      argResults?['ask-before-publishing'] as bool? ?? true;

  bool get _shouldIncreaseVersion =>
      argResults?['increase-version'] as bool? ?? true;

  bool get _deleteFeatureBranchFromArgs =>
      argResults?['delete-feature-branch'] as bool? ?? false;

  bool get _deleteFeatureBranchWasProvided =>
      argResults?.wasParsed('delete-feature-branch') ?? false;

  String? get _messageFromArgs => argResults?['message'] as String?;

  // coverage:ignore-start
  static bool _defaultConfirmDeleteFeatureBranch(String branchName) {
    final selection = Select(
      prompt: 'Delete feature branch $branchName on origin?',
      options: const <String>['Yes', 'No'],
      initialIndex: 1,
    ).interact();

    return selection == 0;
  }

  /// Opens an interactive editor for the merge message.
  static Future<String?> _defaultEditMessage(String initialMessage) async {
    return Input(
      prompt: 'Edit merge message',
      defaultValue: initialMessage,
      initialText: initialMessage,
    ).interact();
  }
  // coverage:ignore-end

  void _addArgs() {
    argParser.addFlag(
      'ask-before-publishing',
      abbr: 'a',
      help: 'Ask for confirmation before publishing to pub.dev.',
      defaultsTo: true,
      negatable: true,
    );

    argParser.addFlag(
      'increase-version',
      abbr: 'c',
      help: 'Increase version after publishing.',
      defaultsTo: true,
      negatable: true,
    );

    argParser.addFlag(
      'delete-feature-branch',
      help: 'Delete the current feature branch on origin after publishing.',
      defaultsTo: false,
      negatable: true,
    );

    argParser.addOption(
      'message',
      abbr: 'm',
      help: 'The merge commit message used for the final merge step.',
    );

    argParser.addOption(
      'config',
      help:
          'Path to a .gg-publish.json file with merge_message and '
          'version_increment. Resolved as-given (CWD), then under '
          '"<repo>/.gg/".',
    );

    argParser.addFlag(
      'verbose',
      abbr: 'v',
      help: 'Prints each executed command before running it.',
      defaultsTo: false,
      negatable: false,
    );
  }
}

/// Mock for [DoPublish].
class MockDoPublish extends MockDirCommand<void> implements DoPublish {}
