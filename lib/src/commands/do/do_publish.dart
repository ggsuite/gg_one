// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_one/gg_one.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_changelog/gg_changelog.dart' as changelog;
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_git/gg_git.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_merge/gg_merge.dart' as gg_merge;
import 'package:gg_process/gg_process.dart';
import 'package:gg_publish/gg_publish.dart';
import 'package:gg_version/gg_version.dart';
import 'package:path/path.dart';
import 'package:pub_semver/pub_semver.dart';

/// Publishes the current directory.
///
/// All interactive decisions (version increment, merge message, feature
/// branch deletion) are resolved up front — from explicit parameters,
/// `--config`, an existing `.gg/.gg-publish.json` or an automatic
/// `do configure-publish` — so no prompt ever sits between the irreversible
/// publish steps. While the publish runs, its per-step progress is recorded
/// in `<repo>/.gg/.gg-publish.json` (see [allowedPublishSteps]); a failed
/// run can be resumed with `--continue` and skips the steps already done.
/// The file is deleted after a fully successful publish.
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
    DidCommit? didCommit,
    PrepareNextVersion? prepareNextVersion,
    FromPubspec? fromPubspec,
    IsPublished? isPublished,
    changelog.Release? release,
    PublishTo? publishTo,
    DoMerge? doMerge,
    PublishedVersion? publishedVersion,
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
    LocalBranch? localBranch,
    ConfirmDeleteFeatureBranch? confirmDeleteFeatureBranch,
    DoConfigurePublish? configurePublish,
    EnsurePublishConfigIgnored? ensureIgnored,
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
       _didCommit = didCommit ?? DidCommit(ggLog: ggLog),
       _prepareNextVersion =
           prepareNextVersion ?? PrepareNextVersion(ggLog: ggLog),
       _fromPubspec = fromPubspec ?? FromPubspec(ggLog: ggLog),
       _releaseChangelog = release ?? changelog.Release(ggLog: ggLog),
       _isPublished = isPublished ?? IsPublished(ggLog: ggLog),
       _publishTo = publishTo ?? PublishTo(ggLog: ggLog),
       _doMerge = doMerge ?? DoMerge(ggLog: ggLog),
       _publishedVersion = publishedVersion,
       _processWrapper = processWrapper,
       _localBranch = localBranch ?? LocalBranch(ggLog: ggLog),
       _confirmDeleteFeatureBranch =
           confirmDeleteFeatureBranch ??
           DoConfigurePublish.defaultConfirmDeleteFeatureBranch,
       _configurePublish = configurePublish ?? DoConfigurePublish(ggLog: ggLog),
       _ensureIgnored =
           ensureIgnored ?? EnsurePublishConfigIgnored(ggLog: ggLog) {
    // coverage:ignore-end
    _addArgs();
  }

  /// The key used to save the state of the command.
  final String stateKey = 'doPublish';

  /// The key used to save the "all changes committed" state (checked by the
  /// pre-push hook via »gg did commit«).
  final String stateKeyDoCommit = 'doCommit';

  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
    bool? askBeforePublishing,
    String? message,
    bool? deleteFeatureBranch,
    bool? verbose,
    String? versionIncrement,
    String? channel,
    bool? resume,
  }) => get(
    directory: directory,
    ggLog: ggLog,
    askBeforePublishing: askBeforePublishing,
    message: message,
    deleteFeatureBranch: deleteFeatureBranch,
    verbose: verbose,
    versionIncrement: versionIncrement,
    channel: channel,
    resume: resume,
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
    String? channel,
    bool? resume,
  }) async {
    final isVerbose = verbose ?? _verboseFromArgs;
    _publishedVersion ??= PublishedVersion(ggLog: ggLog);

    // Does directory exist?
    await check(directory: directory);
    void noLog(_) {} // coverage:ignore-line

    final cliContinue = argResults?['continue'] as bool? ?? false;
    final reconfigure = argResults?['reconfigure'] as bool? ?? false;
    final configArg = argResults?['config'] as String?;
    message ??= _messageFromArgs;

    if (cliContinue && (configArg != null || reconfigure)) {
      throw Exception(
        '--continue cannot be combined with --config or --reconfigure. '
        'Resume with "--continue" alone, or start a fresh run without it.',
      );
    }

    // Step 1: Read the runtime .gg/.gg-publish.json (config + progress).
    final runtimeFile = DoConfigurePublish.configFileFor(directory);
    if (cliContinue && !runtimeFile.existsSync()) {
      throw Exception(
        'Nothing to continue: ${runtimeFile.path} does not exist. Start a '
        'normal "gg do publish" first.',
      );
    }
    if (reconfigure && runtimeFile.existsSync()) {
      // Explicit user choice: discard the previous config and progress.
      runtimeFile.deleteSync();
    }
    final PublishConfig? runtimeConfig = runtimeFile.existsSync()
        ? PublishConfig.load(
            configArg: runtimeFile.path,
            fallbackDir: directory.path,
          )
        : null;

    // A resumed run continues at the first step that is not done yet.
    // gg_multi forwards its own --continue via [resume].
    final resuming =
        (cliContinue || (resume ?? false)) &&
        (runtimeConfig?.hasStepProgress ?? false);

    if (!resuming && (runtimeConfig?.hasStepProgress ?? false)) {
      throw Exception(
        'An unfinished publish left progress in ${runtimeFile.path}. '
        'Resume it with "gg do publish --continue", or discard it with '
        '"gg do publish --reconfigure".',
      );
    }

    // Step 2: Did already publish? Only trusted when no in-flight progress
    // exists — a leftover progress file means later steps (e.g. the tag)
    // still have to run.
    final isDone = await _state.readSuccess(
      directory: directory,
      key: stateKey,
      ggLog: ggLog,
    );
    if (isDone && !resuming) {
      ggLog(yellow('Current state is already published.'));
      return;
    }

    // Step 3: Make the runtime file invisible to git before it is written.
    await _ensureIgnored.ensure(directory: directory);

    // Step 4: Resolve version increment, merge message and the
    // delete-feature-branch decision. Precedence: explicit parameters (the
    // gg_multi flow) / CLI flags > --config > the runtime
    // .gg/.gg-publish.json > an interactive `do configure-publish`. Every
    // interactive decision happens HERE — never between the irreversible
    // publish steps.
    String? resolvedIncrement = versionIncrement;
    String? resolvedMessage = message;
    String? resolvedChannel = channel ?? _channelFromArgs;
    bool? resolvedDelete = deleteFeatureBranch;
    if (resolvedDelete == null && _deleteFeatureBranchWasProvided) {
      resolvedDelete = _deleteFeatureBranchFromArgs;
    }
    if (resolvedIncrement == null || resolvedMessage == null) {
      if (configArg != null) {
        final config = PublishConfig.load(
          configArg: configArg,
          fallbackDir: join(directory.path, '.gg'),
        );
        final resolved = config.resolveSingle(configPath: configArg);
        resolvedIncrement ??= resolved.versionIncrement;
        resolvedMessage ??= resolved.mergeMessage;
        resolvedChannel ??= config.channel;
        resolvedDelete ??= config.deleteFeatureBranch;
      } else if (runtimeConfig != null) {
        final resolved = runtimeConfig.resolveSingle(
          configPath: runtimeFile.path,
        );
        resolvedIncrement ??= resolved.versionIncrement;
        resolvedMessage ??= resolved.mergeMessage;
        resolvedChannel ??= runtimeConfig.channel;
        resolvedDelete ??= runtimeConfig.deleteFeatureBranch;
      } else {
        final config = await _configurePublish.configure(
          directory: directory,
          ggLog: ggLog,
          versionIncrement: resolvedIncrement,
          mergeMessage: resolvedMessage,
          deleteFeatureBranch: resolvedDelete,
        );
        resolvedIncrement = config.versionIncrement;
        resolvedMessage = config.mergeMessage;
        resolvedChannel ??= config.channel;
        resolvedDelete ??= config.deleteFeatureBranch;
      }
    } else {
      // Increment + message came as parameters, only the channel and delete
      // decisions may be open — read them from the config file when one is
      // present.
      resolvedChannel ??= runtimeConfig?.channel;
      resolvedDelete ??= runtimeConfig?.deleteFeatureBranch;
    }
    resolvedChannel ??= 'stable';
    _explicitVersionIncrement = resolvedIncrement;
    _explicitChannel = resolvedChannel;

    // The feature branch is persisted in the runtime file: a resumed run may
    // find HEAD on the default branch already (the merge happened), so it
    // must not be re-read from HEAD then. Only a RESUMED run may trust the
    // persisted value — a leftover file from a run that failed before its
    // first step (e.g. in canPublish) must not pin a stale branch that a
    // later publish of a different branch would then delete.
    final featureBranch =
        (resuming ? runtimeConfig?.branch : null) ??
        await _localBranch.get(directory: directory, ggLog: <String>[].add);

    // A config source that predates the delete_feature_branch field (or an
    // explicit --config without it) leaves the decision open — ask NOW,
    // before anything irreversible runs. In non-interactive environments the
    // default prompt fails fast instead of hanging.
    resolvedDelete ??= _confirmDeleteFeatureBranch(featureBranch);

    // Step 5: Persist the resolved config (+ carried-over progress) as the
    // runtime file — the resume anchor for this run. The delete decision is
    // stored too, so a resumed run never has to re-ask.
    var progress = PublishConfig(
      versionIncrement: resolvedIncrement,
      mergeMessage: resolvedMessage,
      channel: resolvedChannel,
      deleteFeatureBranch: resolvedDelete,
      branch: featureBranch,
      doneSteps: resuming ? runtimeConfig!.doneSteps : null,
    );
    await progress.save(file: runtimeFile);

    Future<void> markStepDone(String step) async {
      progress = progress.withStepDone(step);
      await progress.save(file: runtimeFile);
    }

    // Step 6: Validate. The full `can publish` is skipped when resuming —
    // after a partial publish (version bumped, possibly merged) its checks
    // would fail although the remaining steps are perfectly resumable. But
    // commits added AFTER the failed run must not be published unvalidated:
    // »did commit« is hash-keyed and survives gg's own bookkeeping commits,
    // so it fails exactly when raw new commits sneaked in.
    if (resuming) {
      ggLog(
        yellow('Resuming the unfinished publish — "can publish" is skipped.'),
      );
      final didCommit = await _didCommit.get(
        directory: directory,
        ggLog: <String>[].add,
      );
      if (!didCommit) {
        throw Exception(
          'The repository changed since the failed publish. Run '
          '"gg do commit" first, then resume with '
          '"gg do publish --continue".',
        );
      }
    } else {
      await _canPublish.exec(directory: directory, ggLog: ggLog);
    }

    // Protected main branches (e.g. Azure DevOps) reject a direct push to main
    // and require a pull request. Detect that up front and merge via an
    // auto-complete PR (waiting until it is merged) instead of a local merge
    // followed by a direct push to main.
    final viaPullRequest = await _shouldMergeViaPullRequest(directory);

    // A resumed run whose merge already happened may still sit on the
    // feature branch (gg_multi checks it out again after a failure). Move to
    // the default branch BEFORE the first push, so no push resurrects the
    // possibly already-deleted remote feature branch and push/tag target the
    // release commit.
    if (resuming && progress.isStepDone('merge') && !viaPullRequest) {
      await _checkoutDefaultBranch(directory);
    }

    await _doPush.gitPush(directory: directory, force: false);

    // Step 7: Prepare version + changelog.
    if (!progress.isStepDone('prepare_version')) {
      await _prepareVersion(directory: directory, ggLog: ggLog, noLog: noLog);
      await markStepDone('prepare_version');
    }

    // Step 8: Publish to the registry (pub.dev/npm). The registry lookup is
    // a safety net: a version that is already visible must not be published
    // again on a resumed run whose marker got lost.
    if (!progress.isStepDone('publish_registry')) {
      final alreadyPublished = await _versionAlreadyPublished(
        directory: directory,
        ggLog: ggLog,
      );

      if (!alreadyPublished) {
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
      }
      await markStepDone('publish_registry');
    }

    // Step 9: Merge into the default branch. (When the step is already done
    // on a resumed run, the default branch was checked out before Step 6.)
    if (!progress.isStepDone('merge')) {
      await _merge(
        directory: directory,
        message: resolvedMessage,
        verbose: isVerbose,
        viaPullRequest: viaPullRequest,
      );
      await markStepDone('merge');
    }

    // Save state
    await _state.writeSuccess(directory: directory, key: stateKey);

    // The merge/version commits produced a fully-committed, gg-verified HEAD on
    // the main branch. Record it as »doCommit« too, so the pre-push hook (which
    // runs »gg did commit«) accepts the push instead of rejecting the merge
    // commit.
    await _state.writeSuccess(directory: directory, key: stateKeyDoCommit);

    // In the pull-request flow the provider already updated main and deleted
    // the source branch, so skip the direct main push and branch deletion here.
    if (!viaPullRequest) {
      // Push through DoPush.get, not raw gitPush: it writes the »doPush«
      // success state into .gg/.gg.json (amended into the release commit)
      // before pushing, so »gg did push« passes on a fresh CI checkout of
      // main. The doPush state carried over from the feature branch belongs
      // to an older hash and would make CI red on every released package.
      await _doPush.get(directory: directory, force: false, ggLog: noLog);

      // Step 10: Delete the feature branch. The decision was resolved up
      // front (Step 4). Idempotent instead of tracked: a resumed multi-flow
      // run re-pushes the branch before delegating here, so the deletion
      // must re-run — and deleting an already-gone remote ref is tolerated
      // inside _deleteFeatureBranch.
      if (resolvedDelete) {
        await _deleteFeatureBranch(
          directory: directory,
          branchName: featureBranch,
          verbose: isVerbose,
        );
      }
    }

    // Step 11: Tag the release and push the tags.
    if (!progress.isStepDone('tag')) {
      await _publishGit(directory: directory, ggLog: ggLog);
      await markStepDone('tag');
    }
    await _doPush.gitPush(directory: directory, force: false, pushTags: true);

    // Step 12: Fully published — the runtime file has served its purpose.
    if (runtimeFile.existsSync()) {
      runtimeFile.deleteSync();
    }
  }

  final Publish _publishToPubDev;
  final CanPublish _canPublish;
  final GgState _state;
  final AddVersionTag _addVersionTag;
  final AddTypeScriptVersionTag _addTypeScriptVersionTag;
  final DoPush _doPush;
  final Commit _commit;
  final DidCommit _didCommit;
  final PrepareNextVersion _prepareNextVersion;
  final FromPubspec _fromPubspec;
  final changelog.Release _releaseChangelog;
  final IsPublished _isPublished;
  final PublishTo _publishTo;
  final DoMerge _doMerge;
  PublishedVersion? _publishedVersion;
  final GgProcessWrapper _processWrapper;
  final LocalBranch _localBranch;
  final ConfirmDeleteFeatureBranch _confirmDeleteFeatureBranch;
  final DoConfigurePublish _configurePublish;
  final EnsurePublishConfigIgnored _ensureIgnored;

  /// Pre-resolved version increment; always set before the steps run.
  String? _explicitVersionIncrement;

  /// Pre-resolved release channel; always set before the steps run.
  String? _explicitChannel;

  /// Returns true when the current version is already visible on the
  /// registry, i.e. publishing it again is obsolete.
  Future<bool> _versionAlreadyPublished({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    final currentVersion = await _fromPubspec.get(
      directory: directory,
      ggLog: <String>[].add,
    );
    try {
      // Prereleases never become the registry's "latest" version, so they
      // must be looked up in the full version list instead.
      if (currentVersion.preRelease.isNotEmpty) {
        final allVersions = await _publishedVersion!.allVersions(
          directory: directory,
          ggLog: <String>[].add,
        );
        return allVersions.contains(currentVersion);
      }

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

  /// Performs the merge. On protected branches ([viaPullRequest] true) this
  /// merges through an auto-complete pull request and waits until it is merged;
  /// otherwise it does a local merge into main.
  Future<void> _merge({
    required Directory directory,
    required String? message,
    required bool verbose,
    required bool viaPullRequest,
  }) async {
    await _doMerge.get(
      directory: directory,
      ggLog: verbose ? ggLog : <String>[].add,
      automerge: false,
      local: !viaPullRequest,
      message: message,
      verbose: verbose,
      viaPullRequest: viaPullRequest,
    );
  }

  /// Returns whether the merge must go through a pull request because the main
  /// branch is protected. Uses the git provider of `origin`: Azure DevOps
  /// enforces pull requests for `main` (`TF402455`). A missing/unknown remote
  /// falls back to the local merge.
  Future<bool> _shouldMergeViaPullRequest(Directory directory) async {
    final result = await _processWrapper.run('git', [
      'config',
      '--get',
      'remote.origin.url',
    ], workingDirectory: directory.path);
    if (result.exitCode != 0) {
      return false;
    }
    final url = result.stdout.toString().trim();
    return gg_merge.providerFromRemoteUrl(url) == gg_merge.GitProvider.azure;
  }

  /// Checks out the default branch (`main`/`master`). Used when a resumed run
  /// skips the already-done merge step: the release commit to push and tag
  /// lives on the default branch, not on the feature branch HEAD may be on.
  Future<void> _checkoutDefaultBranch(Directory directory) async {
    final current = await _localBranch.get(
      directory: directory,
      ggLog: <String>[].add,
    );
    for (final candidate in ['main', 'master']) {
      final exists = await _processWrapper.run('git', [
        'rev-parse',
        '--verify',
        '--quiet',
        'refs/heads/$candidate',
      ], workingDirectory: directory.path);
      if (exists.exitCode != 0) {
        continue;
      }
      if (current != candidate) {
        final checkout = await _processWrapper.run('git', [
          'checkout',
          candidate,
        ], workingDirectory: directory.path);
        if (checkout.exitCode != 0) {
          throw Exception('git checkout $candidate failed: ${checkout.stderr}');
        }
        ggLog(yellow('Checked out $candidate to finish the resumed publish.'));
      }
      return;
    }
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
    if (checkProjectType(directory) == ProjectType.typescript) {
      // Bridges tag from package.json too (published as TypeScript).
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

    // The increment and channel are always resolved before the steps run
    // (parameters, --config, runtime file or `do configure-publish`).
    final increment = parseVersionIncrement(_explicitVersionIncrement!);
    final releaseChannel = parseReleaseChannel(_explicitChannel!);

    await _prepareNextVersion.exec(
      directory: directory,
      ggLog: ggLog,
      increment: increment,
      channel: releaseChannel,
      publishedVersion: currentVersion,
    );

    await _state.updateHash(hash: hashBefore, directory: directory);

    final newVersion = await _fromPubspec.fromDirectory(directory: directory);

    try {
      await _commit.commit(
        ggLog: ggLog,
        directory: directory,
        doStage: true,
        message: 'Finish development of version $newVersion',
        ammendWhenNotPushed: false,
      );
    } on Exception catch (e) {
      // When resuming after a failed publish, the version is already bumped
      // and committed, so there is nothing left to commit. Tolerate the empty
      // commit instead of crashing — this keeps »do publish« idempotent.
      if (e.toString().contains('Nothing to commit')) {
        ggLog('Version $newVersion is already prepared — nothing to commit.');
      } else {
        rethrow;
      }
    }
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
      checkProjectType(directory).isDartFamily;

  /// Deletes the provided feature branch on the remote. Idempotent: an
  /// already-deleted remote ref (a resumed run) is tolerated.
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
      final stderr = result.stderr.toString();
      if (stderr.contains('remote ref does not exist')) {
        ggLog(yellow('Remote feature branch $branchName was already deleted.'));
        return;
      }
      throw Exception('git push origin --delete $branchName failed: $stderr');
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

  String? get _channelFromArgs => argResults?['channel'] as String?;

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
      help:
          'The merge commit message used for the final merge step. When '
          'given, the interactive merge-message prompt is skipped.',
    );

    argParser.addOption(
      'config',
      help:
          'Path to a .gg-publish.json file with merge_message and '
          'version_increment. Resolved as-given (CWD), then under '
          '"<repo>/.gg/".',
    );

    argParser.addOption(
      'channel',
      help:
          'The release channel. "rc" publishes the next X.Y.Z-rc.N '
          'prerelease of the target version instead of the stable release.',
      allowed: allowedReleaseChannels,
    );

    argParser.addFlag(
      'continue',
      help:
          'Resume a previously failed publish from where it stopped, '
          'reusing .gg/.gg-publish.json and skipping the steps already done.',
      defaultsTo: false,
      negatable: false,
    );

    argParser.addFlag(
      'reconfigure',
      help:
          'Discard an existing .gg/.gg-publish.json (config and progress) '
          'and configure the publish again.',
      defaultsTo: false,
      negatable: true,
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
