// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// These are git-subprocess-heavy integration tests: setUp plus each
// DoPublish.exec spawn dozens of real `git` processes. Under the parallel
// coverage gate that contention can push the heaviest case past the default
// 30s per-test timeout (it passes comfortably in isolation / at -j1), so we
// give the whole file generous headroom.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_direct_json/gg_direct_json.dart';
import 'package:gg_git/gg_git.dart';
import 'package:gg_git/gg_git_test_helpers.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_merge/gg_merge.dart' as gg_merge;
import 'package:gg_one/gg_one.dart';
import 'package:gg_process/gg_process.dart';
import 'package:gg_publish/gg_publish.dart';
import 'package:gg_version/gg_version.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import '../../test_helpers/test_helpers.dart';

void main() {
  final messages = <String>[];
  final ggLog = messages.add;
  late Directory d;
  late Directory dRemote;
  late Directory Function() dMock;
  late DoPublish doPublish;
  late CanPublish canPublish;
  late PublishedVersion publishedVersion;
  late IsVersionPrepared isVersionPrepared;
  late VersionSelector versionSelector;
  late MockGgProcessWrapper processWrapper;
  late MockLocalBranch localBranch;

  late int successHash;
  late int needsChangeHash;
  late Version publishedVersionValue;

  // ...........................................................................
  // Mocks
  late Publish publish;

  Future<String?> defaultEditMessage(String initialMessage) async {
    return initialMessage;
  }

  bool defaultConfirmDeleteFeatureBranch(String branchName) {
    return false;
  }

  // Builds the DoConfigurePublish that »do publish« runs when it is started
  // without a resolved configuration. Uses the mocked version selector and
  // non-interactive prompts.
  DoConfigurePublish makeConfigurePublish({
    EditMessage? editMessage,
    ConfirmDeleteFeatureBranch? confirmDeleteFeatureBranch,
  }) => DoConfigurePublish(
    ggLog: ggLog,
    versionSelector: versionSelector,
    editMessage: editMessage ?? defaultEditMessage,
    confirmDeleteFeatureBranch:
        confirmDeleteFeatureBranch ?? defaultConfirmDeleteFeatureBranch,
  );

  // DoMerge variant for the bare test repo.
  DoMerge noPubGetDoMerge() => DoMerge(
    ggLog: ggLog,
    doMerge: gg_merge.DoMerge(
      ggLog: ggLog,
      localMerge: gg_merge.LocalMerge(ggLog: ggLog),
    ),
  );

  void mockPublishIsSuccessful({
    required bool success,
    required bool askBeforePublishing,
  }) =>
      when(
        () => publish.exec(
          directory: dMock(),
          ggLog: ggLog,
          askBeforePublishing: askBeforePublishing,
        ),
      ).thenAnswer((_) async {
        if (!success) {
          throw Exception('Publishing failed.');
        } else {
          publishedVersionValue = Version.parse('1.2.4');
          ggLog('Publishing was successful.');
        }
      });

  void mockPublishedVersion() =>
      when(
        () => publishedVersion.get(
          directory: dMock(),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {
        return publishedVersionValue;
      });

  void mockVersionSelector() =>
      when(
        () => versionSelector.selectIncrement(
          currentVersion: any(named: 'currentVersion'),
        ),
      ).thenAnswer((_) async {
        return VersionIncrement.patch;
      });

  // Runs a full single-repo publish on the rc channel and asserts pubspec.yaml
  // ends up at the next rc prerelease. [useCliFlag] chooses between the
  // `--channel rc` CLI flag and a `channel: rc` field in the --config file.
  Future<void> runRcChannelTest({required bool useCliFlag}) async {
    mockPublishIsSuccessful(success: true, askBeforePublishing: false);
    when(
      () => publishedVersion.allVersions(
        directory: dMock(),
        ggLog: any(named: 'ggLog'),
      ),
    ).thenAnswer((_) async => [Version.parse('1.2.3')]);

    final cfgDir = await Directory.systemTemp.createTemp('publish_config_');
    final cfgPath = join(cfgDir.path, 'release.json');
    await File(cfgPath).writeAsString(
      '{"version_increment":"patch", "merge_message":"rc release"'
      '${useCliFlag ? '' : ', "channel":"rc"'}, '
      '"delete_feature_branch":false}',
    );

    final cliDoPublish = DoPublish(
      ggLog: ggLog,
      publish: publish,
      prepareNextVersion: PrepareNextVersion(
        ggLog: ggLog,
        publishedVersion: publishedVersion,
      ),
      canPublish: canPublish,
      isPublished: IsPublished(
        ggLog: ggLog,
        publishedVersion: publishedVersion,
      ),
      configurePublish: makeConfigurePublish(),
      publishedVersion: publishedVersion,
      processWrapper: processWrapper,
      localBranch: localBranch,
      confirmDeleteFeatureBranch: (_) => false,
      doMerge: noPubGetDoMerge(),
    );

    final runner = CommandRunner<void>('gg', 'gg')..addCommand(cliDoPublish);

    await runner.run(<String>[
      'publish',
      '-i',
      d.path,
      '--config',
      cfgPath,
      if (useCliFlag) ...['--channel', 'rc'],
      '--no-ask-before-publishing',
    ]);

    final pubspec = await File(join(d.path, 'pubspec.yaml')).readAsString();
    expect(pubspec, contains('version: 1.2.4-rc.1'));

    cfgDir.deleteSync(recursive: true);
  }

  // ...........................................................................
  Future<void> makeLastStateSuccessful() async {
    successHash = await LastChangesHash(
      ggLog: ggLog,
    ).get(directory: d, ggLog: ggLog, ignoreFiles: GgState.ignoreFiles);

    final ggDir = Directory(join(d.path, '.gg'));
    if (!ggDir.existsSync()) {
      await ggDir.create(recursive: true);
    }

    await File(join(ggDir.path, '.gg.json')).writeAsString(
      '{"canCommit":{"success":{"hash":$successHash}},'
      '"doCommit":{"success":{"hash":$successHash}},'
      '"canPush":{"success":{"hash":$successHash}},'
      '"doPush":{"success":{"hash":$successHash}},'
      '"canPublish":{"success":{"hash":$successHash}}}',
    );
  }

  // ...........................................................................
  Future<void> resetTicketFile() async {
    await File(join(d.path, '.ticket')).writeAsString(
      jsonEncode(<String, String>{
        'issue_id': 'feat_abc',
        'description': 'Ticket merge message',
      }),
    );
  }

  // ...........................................................................
  setUp(() async {
    // Create repositories
    d = await Directory.systemTemp.createTemp('local');
    await initLocalGit(d);
    await enableEolLf(d);
    dRemote = await Directory.systemTemp.createTemp('remote');
    await initRemoteGit(dRemote);
    await addRemoteToLocal(local: d, remote: dRemote);
    publishedVersionValue = Version.parse('1.2.3');

    // Clear messages
    messages.clear();

    // Setup a pubspec.yaml and a CHANGELOG.md with right versions
    await File(join(d.path, 'pubspec.yaml')).writeAsString(
      'name: gg\n\nversion: 1.2.3\n'
      'repository: https://github.com/inlavigo/gg.git',
    );

    // Prepare ChangeLog
    await File(join(d.path, 'CHANGELOG.md')).writeAsString(
      '# Changelog\n\n'
      '## Unreleased\n'
      '-Message 1\n'
      '-Message 2\n'
      '## 1.2.3 - 2024-04-05\n\n- First version',
    );

    await addAndCommitSampleFile(
      d,
      fileName: 'CLAUDE.md',
      content: 'This is the CLAUDE.md',
    );
    final runner = CommandRunner<void>('gg', 'gg')
      ..addCommand(Create(ggLog: ggLog));
    await runner.run([
      'create',
      'ticket',
      '-i',
      d.path,
      'feat_abc',
      '-m',
      'Ticket merge message',
    ]);
    messages.clear();
    await commitFile(d, 'CLAUDE.md');
    await addAndCommitSampleFile(
      d,
      fileName: 'README.md',
      content: 'This is the readme',
    );
    await pushLocalChangesUpstream(d, 'feat_abc');

    // Create a .gg/.gg.json that has all preconditions for publishing
    needsChangeHash = 12345;

    // Mock publishing
    dMock = () => any(
      named: 'directory',
      that: predicate<Directory>((x) => x.path == d.path),
    );
    registerFallbackValue(d);
    publish = MockPublish();
    processWrapper = MockGgProcessWrapper();
    localBranch = MockLocalBranch();

    when(
      () => localBranch.get(
        directory: any(named: 'directory'),
        ggLog: any(named: 'ggLog'),
      ),
    ).thenAnswer((_) async => 'feat_abc');

    when(
      () => processWrapper.run('git', [
        'push',
        'origin',
        '--delete',
        'feat_abc',
      ], workingDirectory: d.path),
    ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

    when(
      () => processWrapper.run('git', [
        'status',
        '--porcelain',
        'pubspec.lock',
      ], workingDirectory: d.path),
    ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

    // Default: a remote without pull-request support → local merge flow.
    when(
      () => processWrapper.run('git', [
        'config',
        '--get',
        'remote.origin.url',
      ], workingDirectory: d.path),
    ).thenAnswer(
      (_) async =>
          ProcessResult(0, 0, 'https://git.example.com/inlavigo/gg.git', ''),
    );

    publishedVersion = MockPublishedVersion();

    isVersionPrepared = IsVersionPrepared(
      ggLog: ggLog,
      publishedVersion: publishedVersion,
    );

    canPublish = CanPublish(ggLog: ggLog, isVersionPrepared: isVersionPrepared);
    mockPublishedVersion();

    versionSelector = MockVersionSelector();
    registerFallbackValue(Version(0, 0, 0));
    mockVersionSelector();

    // Instantiate with mocks
    doPublish = DoPublish(
      ggLog: ggLog,
      publish: publish,
      prepareNextVersion: PrepareNextVersion(
        ggLog: ggLog,
        publishedVersion: publishedVersion,
      ),
      canPublish: canPublish,
      isPublished: IsPublished(
        ggLog: ggLog,
        publishedVersion: publishedVersion,
      ),
      configurePublish: makeConfigurePublish(),
      publishedVersion: publishedVersion,
      processWrapper: processWrapper,
      localBranch: localBranch,
      confirmDeleteFeatureBranch: defaultConfirmDeleteFeatureBranch,
      doMerge: noPubGetDoMerge(),
    );

    await makeLastStateSuccessful();
    messages.clear();
  });

  tearDown(() async {
    await d.delete(recursive: true);
    await dRemote.delete(recursive: true);
  });

  group('DoPublish', () {
    group('exec(directory)', () {
      group('should succeed', () {
        group('and publish', () {
          group('to pub.dev', () {
            group('when no »publish_to: none« is found in pubspec.yaml', () {
              group('when the package', () {
                group('has been published before', () {
                  group('and ask for confirmation', () {
                    for (final ask in [true, null]) {
                      test('when askBeforePublishing is $ask', () async {
                        // Expect asking for confirmation
                        mockPublishIsSuccessful(
                          success: true,
                          askBeforePublishing: true,
                        );
                        publishedVersionValue = Version(1, 2, 3);
                        mockPublishedVersion();

                        messages.clear();

                        // Publish
                        await doPublish.exec(
                          directory: d,
                          ggLog: ggLog,
                          askBeforePublishing: ask,
                          deleteFeatureBranch: false,
                        );

                        final allMessages = messages.join('\n');
                        expect(allMessages, contains('Can publish?'));
                        expect(allMessages, contains('✅ Everything is fine.'));
                        expect(allMessages, contains('⌛️ Increase version'));
                        expect(allMessages, contains('✅ Increase version'));
                        expect(
                          allMessages,
                          contains('Publishing was successful.'),
                        );
                        expect(allMessages, contains('✅ Tag 1.2.4 added.'));

                        // Was a new version created?
                        final pubspec = await File(
                          join(d.path, 'pubspec.yaml'),
                        ).readAsString();
                        final changeLog = await File(
                          join(d.path, 'CHANGELOG.md'),
                        ).readAsString();
                        expect(pubspec, contains('version: 1.2.4'));
                        expect(changeLog, contains('## [1.2.4] -'));

                        // Was the new version checked in?
                        final headMessage = await HeadMessage(
                          ggLog: ggLog,
                        ).get(directory: d, ggLog: ggLog);
                        expect(headMessage, 'Ticket merge message');

                        // Did .gg/.gg.json mark commit, push and publish done?
                        expect(
                          await DidCommit(
                            ggLog: ggLog,
                          ).get(directory: d, ggLog: ggLog),
                          isTrue,
                        );

                        expect(
                          await DidPush(
                            ggLog: ggLog,
                          ).get(directory: d, ggLog: ggLog),
                          isTrue,
                        );
                      });
                    }
                  });

                  group('has not been published before', () {
                    test('and askForConfirmation is true', () async {
                      // Mock that the package was never published before
                      publishedVersionValue = Version(0, 0, 0);
                      mockPublishedVersion();

                      // Expect asking for confirmation
                      mockPublishIsSuccessful(
                        success: true,
                        askBeforePublishing: true,
                      );

                      // Publish
                      await doPublish.exec(
                        directory: d,
                        ggLog: ggLog,
                        askBeforePublishing: true,
                        deleteFeatureBranch: false,
                      );

                      // Check
                    });
                  });
                });
              });

              group('without asking for confirmation', () {
                test('when askBeforePublishing is false', () async {
                  // Expect not asking for confirmation
                  mockPublishIsSuccessful(
                    success: true,
                    askBeforePublishing: false,
                  );

                  // Publish
                  await doPublish.exec(
                    directory: d,
                    ggLog: ggLog,
                    askBeforePublishing: false,
                    deleteFeatureBranch: false,
                  );

                  // Check result
                });
              });
            });
          });

          test('commits pubspec.lock if modified during publishing', () async {
            when(
              () => publish.exec(
                directory: dMock(),
                ggLog: ggLog,
                askBeforePublishing: false,
              ),
            ).thenAnswer((_) async {
              await File(
                join(d.path, 'pubspec.lock'),
              ).writeAsString('packages: {}\n');
              publishedVersionValue = Version.parse('1.2.4');
            });

            when(
              () => processWrapper.run('git', [
                'status',
                '--porcelain',
                'pubspec.lock',
              ], workingDirectory: d.path),
            ).thenAnswer(
              (_) async => ProcessResult(0, 0, ' M pubspec.lock', ''),
            );

            await doPublish.exec(
              directory: d,
              ggLog: ggLog,
              askBeforePublishing: false,
              deleteFeatureBranch: false,
            );

            expect(
              await DidCommit(ggLog: ggLog).get(directory: d, ggLog: ggLog),
              isTrue,
            );
          });

          test('writes the doPush state for the release commit '
              'and pushes the version tag', () async {
            mockPublishIsSuccessful(success: true, askBeforePublishing: false);

            // The doPush state carries a stale hash from development — as on
            // a real feature branch, where the last »gg do push« ran before
            // the release commits existed. Without a fresh doPush state on
            // the release commit, »gg did push« fails on a CI checkout.
            await DirectJson.writeFile(
              file: File(join(d.path, '.gg', '.gg.json')),
              path: 'doPush/success/hash',
              value: needsChangeHash,
            );

            await doPublish.exec(
              directory: d,
              ggLog: ggLog,
              askBeforePublishing: false,
              deleteFeatureBranch: false,
            );

            expect(
              await DidPush(ggLog: ggLog).get(directory: d, ggLog: ggLog),
              isTrue,
            );

            // The version tag must arrive on the remote.
            final remoteTags = await Process.run('git', [
              'tag',
            ], workingDirectory: dRemote.path);
            expect(remoteTags.stdout, contains('1.2.4'));
          });

          group('not to pub.dev', () {
            test('when »publish_to: none« in pubspec.yaml', () async {
              doPublish = DoPublish(
                ggLog: ggLog,
                publish: publish,
                configurePublish: makeConfigurePublish(),
                processWrapper: processWrapper,
                localBranch: localBranch,
                confirmDeleteFeatureBranch: defaultConfirmDeleteFeatureBranch,
                doMerge: noPubGetDoMerge(),
              );

              // Prepare pubspec.yaml
              final pubspecFile = File(join(d.path, 'pubspec.yaml'));
              const currentVersion = '1.0.1';
              await addAndCommitVersions(
                d,
                pubspec: currentVersion,
                changeLog: 'Unreleased',
                gitHead: currentVersion,
                appendToPubspec: '\npublish_to: none',
              );
              var pubspec = await pubspecFile.readAsString();
              expect(pubspec, contains('version: 1.0.1'));

              await makeLastStateSuccessful();

              messages.clear();

              // Publish
              await doPublish.exec(
                directory: d,
                ggLog: ggLog,
                deleteFeatureBranch: false,
              );

              final allMessages = messages.join('\n');
              expect(allMessages, contains('Can publish?'));
              expect(allMessages, contains('✅ Everything is fine.'));
              expect(allMessages, contains('⌛️ Increase version'));
              expect(allMessages, contains('✅ Increase version'));
              expect(allMessages, contains('Tag 1.0.2 added.'));

              // Was a new version created?
              pubspec = await pubspecFile.readAsString();
              final changeLog = await File(
                join(d.path, 'CHANGELOG.md'),
              ).readAsString();
              expect(pubspec, contains('version: 1.0.2'));
              expect(changeLog, contains('## [1.0.2] -'));

              // Was the new version checked in?
              final headMessage = await HeadMessage(
                ggLog: ggLog,
              ).get(directory: d, ggLog: ggLog);
              expect(headMessage, 'Ticket merge message');

              // Did .gg/.gg.json mark commit, push and publish done?
              expect(
                await DidCommit(ggLog: ggLog).get(directory: d, ggLog: ggLog),
                isTrue,
              );

              expect(
                await DidPush(ggLog: ggLog).get(directory: d, ggLog: ggLog),
                isTrue,
              );
            });
          });

          test('passes a custom merge message '
              'to the final merge step', () async {
            const customMessage = 'My custom merge message';

            mockPublishIsSuccessful(success: true, askBeforePublishing: false);

            await doPublish.exec(
              directory: d,
              ggLog: ggLog,
              askBeforePublishing: false,
              message: customMessage,
              deleteFeatureBranch: false,
            );

            final headMessage = await HeadMessage(
              ggLog: ggLog,
            ).get(directory: d, ggLog: ggLog);
            expect(headMessage, customMessage);
          });

          test('loads merge message from .ticket '
              'and allows editing when not provided', () async {
            mockPublishIsSuccessful(success: true, askBeforePublishing: false);

            await File(join(d.path, '.ticket')).writeAsString(
              jsonEncode(<String, String>{
                'issue_id': 'feat_abc',
                'description': 'Ticket merge message',
              }),
            );

            var initialMessage = '';
            final doPublishWithEditor = DoPublish(
              ggLog: ggLog,
              publish: publish,
              prepareNextVersion: PrepareNextVersion(
                ggLog: ggLog,
                publishedVersion: publishedVersion,
              ),
              canPublish: canPublish,
              isPublished: IsPublished(
                ggLog: ggLog,
                publishedVersion: publishedVersion,
              ),
              configurePublish: makeConfigurePublish(
                editMessage: (String message) async {
                  initialMessage = message;
                  return 'Edited merge message';
                },
              ),
              publishedVersion: publishedVersion,
              processWrapper: processWrapper,
              localBranch: localBranch,
              confirmDeleteFeatureBranch: defaultConfirmDeleteFeatureBranch,
              doMerge: noPubGetDoMerge(),
            );

            await doPublishWithEditor.exec(
              directory: d,
              ggLog: ggLog,
              askBeforePublishing: false,
              deleteFeatureBranch: false,
            );

            expect(initialMessage, 'Ticket merge message');

            final headMessage = await HeadMessage(
              ggLog: ggLog,
            ).get(directory: d, ggLog: ggLog);
            expect(headMessage, 'Edited merge message');
          });

          test('uses empty initial merge message when '
              '.ticket is missing and message is not provided', () async {
            mockPublishIsSuccessful(success: true, askBeforePublishing: false);
            final ticketFile = File(join(d.path, '.ticket'));
            if (await ticketFile.exists()) {
              await ticketFile.delete();
            }

            // commit deletion and refresh state hashes
            await commitFile(d, '.ticket');
            await makeLastStateSuccessful();

            var initialMessage = 'not set';
            final doPublishWithEditor = DoPublish(
              ggLog: ggLog,
              publish: publish,
              prepareNextVersion: PrepareNextVersion(
                ggLog: ggLog,
                publishedVersion: publishedVersion,
              ),
              canPublish: canPublish,
              isPublished: IsPublished(
                ggLog: ggLog,
                publishedVersion: publishedVersion,
              ),
              configurePublish: makeConfigurePublish(
                editMessage: (String message) async {
                  initialMessage = message;
                  return 'Edited without ticket';
                },
              ),
              publishedVersion: publishedVersion,
              processWrapper: processWrapper,
              localBranch: localBranch,
              confirmDeleteFeatureBranch: defaultConfirmDeleteFeatureBranch,
              doMerge: noPubGetDoMerge(),
            );

            await doPublishWithEditor.exec(
              directory: d,
              ggLog: ggLog,
              askBeforePublishing: false,
              deleteFeatureBranch: false,
            );

            expect(initialMessage, '');

            final headMessage = await HeadMessage(
              ggLog: ggLog,
            ).get(directory: d, ggLog: ggLog);
            expect(headMessage, 'Edited without ticket');
          });

          test('does not open editor when merge '
              'message is provided programmatically', () async {
            mockPublishIsSuccessful(success: true, askBeforePublishing: false);

            await File(join(d.path, '.ticket')).writeAsString(
              jsonEncode(<String, String>{
                'issue_id': 'feat_abc',
                'description': 'Ticket merge message',
              }),
            );

            final doPublishWithEditor = DoPublish(
              ggLog: ggLog,
              publish: publish,
              prepareNextVersion: PrepareNextVersion(
                ggLog: ggLog,
                publishedVersion: publishedVersion,
              ),
              canPublish: canPublish,
              isPublished: IsPublished(
                ggLog: ggLog,
                publishedVersion: publishedVersion,
              ),
              configurePublish: makeConfigurePublish(
                editMessage: (_) async {
                  fail('Editor must not be opened when message is provided.');
                },
              ),
              publishedVersion: publishedVersion,
              processWrapper: processWrapper,
              localBranch: localBranch,
              confirmDeleteFeatureBranch: defaultConfirmDeleteFeatureBranch,
              doMerge: noPubGetDoMerge(),
            );

            await doPublishWithEditor.exec(
              directory: d,
              ggLog: ggLog,
              askBeforePublishing: false,
              message: 'Programmatic merge message',
              deleteFeatureBranch: false,
            );

            final headMessage = await HeadMessage(
              ggLog: ggLog,
            ).get(directory: d, ggLog: ggLog);
            expect(headMessage, 'Programmatic merge message');
          });

          test(
            'deletes the feature branch when requested explicitly',
            () async {
              mockPublishIsSuccessful(
                success: true,
                askBeforePublishing: false,
              );

              await doPublish.exec(
                directory: d,
                ggLog: ggLog,
                askBeforePublishing: false,
                deleteFeatureBranch: true,
              );

              verify(
                () => processWrapper.run('git', [
                  'push',
                  'origin',
                  '--delete',
                  'feat_abc',
                ], workingDirectory: d.path),
              ).called(1);
              expect(
                messages[messages.length - 2],
                contains('Deleted remote feature branch feat_abc.'),
              );
            },
          );

          test(
            'does not delete the feature branch when disabled explicitly',
            () async {
              mockPublishIsSuccessful(
                success: true,
                askBeforePublishing: false,
              );

              await doPublish.exec(
                directory: d,
                ggLog: ggLog,
                askBeforePublishing: false,
                deleteFeatureBranch: false,
              );

              verifyNever(
                () => processWrapper.run('git', [
                  'push',
                  'origin',
                  '--delete',
                  'feat_abc',
                ], workingDirectory: d.path),
              );
            },
          );

          test('asks whether to delete the feature branch when not specified — '
              'up front, inside configure-publish', () async {
            mockPublishIsSuccessful(success: true, askBeforePublishing: false);

            var promptBranchName = '';
            final doPublishWithPrompt = DoPublish(
              ggLog: ggLog,
              publish: publish,
              prepareNextVersion: PrepareNextVersion(
                ggLog: ggLog,
                publishedVersion: publishedVersion,
              ),
              canPublish: canPublish,
              isPublished: IsPublished(
                ggLog: ggLog,
                publishedVersion: publishedVersion,
              ),
              // The decision is asked by configure-publish — before the
              // publish pipeline starts, never between its steps.
              configurePublish: makeConfigurePublish(
                confirmDeleteFeatureBranch: (branchName) {
                  promptBranchName = branchName;
                  return true;
                },
              ),
              publishedVersion: publishedVersion,
              processWrapper: processWrapper,
              localBranch: localBranch,
              confirmDeleteFeatureBranch: (_) =>
                  fail('DoPublish itself must not prompt here.'),
              doMerge: noPubGetDoMerge(),
            );

            await doPublishWithPrompt.exec(
              directory: d,
              ggLog: ggLog,
              askBeforePublishing: false,
            );

            expect(promptBranchName, 'feat_abc');
            verify(
              () => processWrapper.run('git', [
                'push',
                'origin',
                '--delete',
                'feat_abc',
              ], workingDirectory: d.path),
            ).called(1);
          });

          test(
            'asks up front when the config file lacks delete_feature_branch',
            () async {
              mockPublishIsSuccessful(
                success: true,
                askBeforePublishing: false,
              );
              // Config-only runtime file without the new field.
              File(join(d.path, '.gg', '.gg-publish.json')).writeAsStringSync(
                '{"version_increment":"patch","merge_message":"msg"}',
              );

              var promptBranchName = '';
              final doPublishWithPrompt = DoPublish(
                ggLog: ggLog,
                publish: publish,
                prepareNextVersion: PrepareNextVersion(
                  ggLog: ggLog,
                  publishedVersion: publishedVersion,
                ),
                canPublish: canPublish,
                isPublished: IsPublished(
                  ggLog: ggLog,
                  publishedVersion: publishedVersion,
                ),
                configurePublish: makeConfigurePublish(
                  editMessage: (_) async =>
                      fail('Config exists — configure must not run.'),
                ),
                publishedVersion: publishedVersion,
                processWrapper: processWrapper,
                localBranch: localBranch,
                confirmDeleteFeatureBranch: (branchName) {
                  promptBranchName = branchName;
                  return true;
                },
                doMerge: noPubGetDoMerge(),
              );

              await doPublishWithPrompt.exec(
                directory: d,
                ggLog: ggLog,
                askBeforePublishing: false,
              );

              expect(promptBranchName, 'feat_abc');
              verify(
                () => processWrapper.run('git', [
                  'push',
                  'origin',
                  '--delete',
                  'feat_abc',
                ], workingDirectory: d.path),
              ).called(1);
            },
          );

          test('reads delete_feature_branch from the config file', () async {
            mockPublishIsSuccessful(success: true, askBeforePublishing: false);
            File(join(d.path, '.gg', '.gg-publish.json')).writeAsStringSync(
              '{"version_increment":"patch","merge_message":"msg",'
              '"delete_feature_branch":true}',
            );

            final headlessPublish = DoPublish(
              ggLog: ggLog,
              publish: publish,
              prepareNextVersion: PrepareNextVersion(
                ggLog: ggLog,
                publishedVersion: publishedVersion,
              ),
              canPublish: canPublish,
              isPublished: IsPublished(
                ggLog: ggLog,
                publishedVersion: publishedVersion,
              ),
              configurePublish: makeConfigurePublish(
                editMessage: (_) async =>
                    fail('Config exists — configure must not run.'),
              ),
              publishedVersion: publishedVersion,
              processWrapper: processWrapper,
              localBranch: localBranch,
              confirmDeleteFeatureBranch: (_) =>
                  fail('The config decides — no prompt allowed.'),
              doMerge: noPubGetDoMerge(),
            );

            await headlessPublish.exec(
              directory: d,
              ggLog: ggLog,
              askBeforePublishing: false,
            );

            verify(
              () => processWrapper.run('git', [
                'push',
                'origin',
                '--delete',
                'feat_abc',
              ], workingDirectory: d.path),
            ).called(1);
          });

          test('uses CLI delete-feature-branch flag when provided', () async {
            mockPublishIsSuccessful(success: true, askBeforePublishing: false);

            final cliDoPublish = DoPublish(
              ggLog: ggLog,
              publish: publish,
              prepareNextVersion: PrepareNextVersion(
                ggLog: ggLog,
                publishedVersion: publishedVersion,
              ),
              canPublish: canPublish,
              isPublished: IsPublished(
                ggLog: ggLog,
                publishedVersion: publishedVersion,
              ),
              configurePublish: makeConfigurePublish(),
              publishedVersion: publishedVersion,
              processWrapper: processWrapper,
              localBranch: localBranch,
              confirmDeleteFeatureBranch: (_) {
                fail('Prompt must not be used when flag is provided.');
              },
              doMerge: noPubGetDoMerge(),
            );

            final runner = CommandRunner<void>('gg', 'gg')
              ..addCommand(cliDoPublish);

            await runner.run([
              'publish',
              '-i',
              d.path,
              '--no-ask-before-publishing',
              '--delete-feature-branch',
            ]);

            verify(
              () => processWrapper.run('git', [
                'push',
                'origin',
                '--delete',
                'feat_abc',
              ], workingDirectory: d.path),
            ).called(1);
          });

          test('reads version_increment + merge_message from --config '
              'when neither is supplied on the CLI', () async {
            // Covers the single-repo `--config` resolve path.
            mockPublishIsSuccessful(success: true, askBeforePublishing: false);

            // Config sits outside the repo to keep the working tree clean.
            final cfgDir = await Directory.systemTemp.createTemp(
              'publish_config_',
            );
            final cfgPath = join(cfgDir.path, 'release.json');
            await File(cfgPath).writeAsString(
              '{"version_increment":"patch", '
              '"merge_message":"from .gg-publish.json", '
              '"delete_feature_branch":false}',
            );

            // Editor must stay shut when --config supplies both fields.
            final cliDoPublish = DoPublish(
              ggLog: ggLog,
              publish: publish,
              prepareNextVersion: PrepareNextVersion(
                ggLog: ggLog,
                publishedVersion: publishedVersion,
              ),
              canPublish: canPublish,
              isPublished: IsPublished(
                ggLog: ggLog,
                publishedVersion: publishedVersion,
              ),
              configurePublish: makeConfigurePublish(
                editMessage: (String initial) async {
                  fail(
                    'Editor must not be opened when --config supplies the '
                    'merge_message (got initialMessage="$initial").',
                  );
                },
              ),
              publishedVersion: publishedVersion,
              processWrapper: processWrapper,
              localBranch: localBranch,
              // delete_feature_branch comes from the --config file — no
              // prompt and no CLI flag needed.
              confirmDeleteFeatureBranch: (_) =>
                  fail('The --config file decides — no prompt allowed.'),
              doMerge: noPubGetDoMerge(),
            );

            final runner = CommandRunner<void>('gg', 'gg')
              ..addCommand(cliDoPublish);

            await runner.run(<String>[
              'publish',
              '-i',
              d.path,
              '--config',
              cfgPath,
              '--no-ask-before-publishing',
            ]);

            // Reaching here proves the load+resolve path ran successfully.

            cfgDir.deleteSync(recursive: true);
          });

          test('publishes an rc prerelease when --config sets channel: rc', () {
            return runRcChannelTest(useCliFlag: false);
          });

          test('publishes an rc prerelease via the --channel rc flag', () {
            return runRcChannelTest(useCliFlag: true);
          });

          test('logs each executed command when --verbose is set', () async {
            mockPublishIsSuccessful(success: true, askBeforePublishing: false);

            final cliDoPublish = DoPublish(
              ggLog: ggLog,
              publish: publish,
              prepareNextVersion: PrepareNextVersion(
                ggLog: ggLog,
                publishedVersion: publishedVersion,
              ),
              canPublish: canPublish,
              isPublished: IsPublished(
                ggLog: ggLog,
                publishedVersion: publishedVersion,
              ),
              configurePublish: makeConfigurePublish(),
              publishedVersion: publishedVersion,
              processWrapper: processWrapper,
              localBranch: localBranch,
              confirmDeleteFeatureBranch: (_) => false,
              doMerge: noPubGetDoMerge(),
            );

            final runner = CommandRunner<void>('gg', 'gg')
              ..addCommand(cliDoPublish);

            await runner.run([
              'publish',
              '-i',
              d.path,
              '--no-ask-before-publishing',
              '--no-delete-feature-branch',
              '--verbose',
            ]);

            expect(
              messages,
              contains('\$ git status --porcelain pubspec.lock'),
            );
          });

          test(
            'uses CLI no-delete-feature-branch flag when provided',
            () async {
              mockPublishIsSuccessful(
                success: true,
                askBeforePublishing: false,
              );

              final cliDoPublish = DoPublish(
                ggLog: ggLog,
                publish: publish,
                prepareNextVersion: PrepareNextVersion(
                  ggLog: ggLog,
                  publishedVersion: publishedVersion,
                ),
                canPublish: canPublish,
                isPublished: IsPublished(
                  ggLog: ggLog,
                  publishedVersion: publishedVersion,
                ),
                configurePublish: makeConfigurePublish(),
                publishedVersion: publishedVersion,
                processWrapper: processWrapper,
                localBranch: localBranch,
                confirmDeleteFeatureBranch: (_) {
                  fail('Prompt must not be used when flag is provided.');
                },
                doMerge: noPubGetDoMerge(),
              );

              final runner = CommandRunner<void>('gg', 'gg')
                ..addCommand(cliDoPublish);

              await runner.run([
                'publish',
                '-i',
                d.path,
                '--no-ask-before-publishing',
                '--no-delete-feature-branch',
              ]);

              verifyNever(
                () => processWrapper.run('git', [
                  'push',
                  'origin',
                  '--delete',
                  'feat_abc',
                ], workingDirectory: d.path),
              );
            },
          );

          test(
            'uses CLI message without opening editor when provided',
            () async {
              mockPublishIsSuccessful(
                success: true,
                askBeforePublishing: false,
              );

              await resetTicketFile();

              final cliDoPublish = DoPublish(
                ggLog: ggLog,
                publish: publish,
                prepareNextVersion: PrepareNextVersion(
                  ggLog: ggLog,
                  publishedVersion: publishedVersion,
                ),
                canPublish: canPublish,
                isPublished: IsPublished(
                  ggLog: ggLog,
                  publishedVersion: publishedVersion,
                ),
                configurePublish: makeConfigurePublish(
                  editMessage: (_) async {
                    fail(
                      'Editor must not be opened when CLI message is provided.',
                    );
                  },
                ),
                publishedVersion: publishedVersion,
                processWrapper: processWrapper,
                localBranch: localBranch,
                confirmDeleteFeatureBranch: defaultConfirmDeleteFeatureBranch,
                doMerge: noPubGetDoMerge(),
              );

              final runner = CommandRunner<void>('gg', 'gg')
                ..addCommand(cliDoPublish);

              await runner.run([
                'publish',
                '-i',
                d.path,
                '--no-ask-before-publishing',
                '--message',
                'CLI merge message',
                '--no-delete-feature-branch',
              ]);

              final headMessage = await HeadMessage(
                ggLog: ggLog,
              ).get(directory: d, ggLog: ggLog);
              expect(headMessage, 'CLI merge message');
            },
          );
        });
      });

      group('and throw', () {
        group('when the package is published the first time', () {
          group('has not been published before', () {
            test('and askForConfirmation is false', () async {
              // Mock that the package was never published before
              publishedVersionValue = Version(0, 0, 0);
              mockPublishedVersion();

              // Publish with askBeforePublishing = false
              late String exception;

              try {
                await doPublish.exec(
                  directory: d,
                  ggLog: ggLog,
                  askBeforePublishing: false,
                  deleteFeatureBranch: false,
                );
              } catch (e) {
                exception = e.toString();
              }

              // Should throw
              expect(
                exception,
                contains(
                  'Please call »gg do push« with »--ask-before-publishing«',
                ),
              );

              // Check
            });
          });
        });

        test('when deleting the feature branch fails', () async {
          mockPublishIsSuccessful(success: true, askBeforePublishing: false);

          when(
            () => processWrapper.run('git', [
              'push',
              'origin',
              '--delete',
              'feat_abc',
            ], workingDirectory: d.path),
          ).thenAnswer((_) async => ProcessResult(0, 1, '', 'Some error'));

          late String exception;

          try {
            await doPublish.exec(
              directory: d,
              ggLog: ggLog,
              askBeforePublishing: false,
              deleteFeatureBranch: true,
            );
          } catch (e) {
            exception = e.toString();
          }

          expect(
            exception,
            'Exception: git push origin --delete feat_abc failed: Some error',
          );
        });
      });
    });

    group('on a TypeScript project', () {
      test(
        'tags HEAD via AddTypeScriptVersionTag instead of the CHANGELOG flow',
        () async {
          // Turn the Dart repo into a TypeScript one: drop pubspec.yaml and
          // CHANGELOG.md, add a versioned package.json and a tsconfig.json.
          await File(join(d.path, 'pubspec.yaml')).delete();
          final changelog = File(join(d.path, 'CHANGELOG.md'));
          if (changelog.existsSync()) {
            await changelog.delete();
          }
          await addAndCommitSampleFile(
            d,
            fileName: 'package.json',
            content: '{"name": "x", "version": "1.2.3"}',
          );
          await addAndCommitSampleFile(
            d,
            fileName: 'tsconfig.json',
            content: '{}',
          );

          // Recompute the success state for the new TypeScript working tree.
          await makeLastStateSuccessful();

          // The TS lock file (package-lock.json) is unchanged.
          when(
            () => processWrapper.run('git', [
              'status',
              '--porcelain',
              'package-lock.json',
            ], workingDirectory: d.path),
          ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

          // The TS version tag is added via the (mocked) process wrapper.
          when(
            () => processWrapper.run('git', [
              'tag',
              '--points-at',
              'HEAD',
            ], workingDirectory: d.path),
          ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
          when(
            () => processWrapper.run('git', [
              'tag',
              '-a',
              '1.2.4',
              '-m',
              'Version 1.2.4',
            ], workingDirectory: d.path),
          ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

          mockPublishIsSuccessful(success: true, askBeforePublishing: false);
          publishedVersionValue = Version(1, 2, 3);
          mockPublishedVersion();

          messages.clear();

          await doPublish.exec(
            directory: d,
            ggLog: ggLog,
            askBeforePublishing: false,
            deleteFeatureBranch: false,
          );

          final allMessages = messages.join('\n');
          expect(allMessages, contains('Publishing was successful.'));
          // The TypeScript tag path (do_publish.dart `_publishGit`) ran.
          expect(allMessages, contains('Tag 1.2.4 added.'));

          // package.json was bumped and no CHANGELOG was (re)created.
          final packageJson = await File(
            join(d.path, 'package.json'),
          ).readAsString();
          expect(packageJson, contains('1.2.4'));
          expect(File(join(d.path, 'CHANGELOG.md')).existsSync(), isFalse);

          // The TS tag creation went through the process wrapper.
          verify(
            () => processWrapper.run('git', [
              'tag',
              '-a',
              '1.2.4',
              '-m',
              'Version 1.2.4',
            ], workingDirectory: d.path),
          ).called(1);
        },
      );

      // Builds a DoPublish whose version commit is driven by [commit], on a
      // TypeScript working tree (no CHANGELOG step).
      Future<DoPublish> tsDoPublishWith(Commit commit) async {
        await File(join(d.path, 'pubspec.yaml')).delete();
        final changelog = File(join(d.path, 'CHANGELOG.md'));
        if (changelog.existsSync()) {
          await changelog.delete();
        }
        await addAndCommitSampleFile(
          d,
          fileName: 'package.json',
          content: '{\n  "name": "x",\n  "version": "1.2.3"\n}\n',
        );
        await addAndCommitSampleFile(
          d,
          fileName: 'tsconfig.json',
          content: '{}',
        );
        await makeLastStateSuccessful();

        mockPublishIsSuccessful(success: true, askBeforePublishing: false);
        publishedVersionValue = Version(1, 2, 3);
        mockPublishedVersion();

        return DoPublish(
          ggLog: ggLog,
          publish: publish,
          commit: commit,
          prepareNextVersion: PrepareNextVersion(
            ggLog: ggLog,
            publishedVersion: publishedVersion,
          ),
          canPublish: canPublish,
          isPublished: IsPublished(
            ggLog: ggLog,
            publishedVersion: publishedVersion,
          ),
          configurePublish: makeConfigurePublish(),
          publishedVersion: publishedVersion,
          processWrapper: processWrapper,
          localBranch: localBranch,
          confirmDeleteFeatureBranch: defaultConfirmDeleteFeatureBranch,
          doMerge: noPubGetDoMerge(),
        );
      }

      test('tolerates an empty version commit when resuming', () async {
        // Resuming after a failed publish: the version is already committed,
        // so the commit reports "Nothing to commit" — »do publish« must keep
        // going instead of crashing.
        final commit = _MockCommit();
        when(
          () => commit.commit(
            ggLog: any(named: 'ggLog'),
            directory: any(named: 'directory'),
            doStage: any(named: 'doStage'),
            message: any(named: 'message'),
            ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
          ),
        ).thenThrow(Exception('Nothing to commit. No uncommitted changes.'));

        final doPublish = await tsDoPublishWith(commit);
        messages.clear();

        // The downstream merge is not the subject here; we only assert the
        // idempotent branch logged its message before continuing.
        try {
          await doPublish.exec(
            directory: d,
            ggLog: ggLog,
            askBeforePublishing: false,
            deleteFeatureBranch: false,
          );
        } catch (_) {
          // ignore later steps
        }

        expect(
          messages.join('\n'),
          contains('Version 1.2.4 is already prepared — nothing to commit.'),
        );
      });

      test('rethrows non-empty-commit failures during version bump', () async {
        final commit = _MockCommit();
        when(
          () => commit.commit(
            ggLog: any(named: 'ggLog'),
            directory: any(named: 'directory'),
            doStage: any(named: 'doStage'),
            message: any(named: 'message'),
            ammendWhenNotPushed: any(named: 'ammendWhenNotPushed'),
          ),
        ).thenThrow(Exception('disk full'));

        final doPublish = await tsDoPublishWith(commit);
        messages.clear();

        late String exception;
        try {
          await doPublish.exec(
            directory: d,
            ggLog: ggLog,
            askBeforePublishing: false,
            deleteFeatureBranch: false,
          );
        } catch (e) {
          exception = e.toString();
        }

        expect(exception, contains('disk full'));
      });
    });

    group('merge strategy detection', () {
      test('uses the local merge flow when origin has no remote', () async {
        // git config exits non-zero → no provider → local merge.
        when(
          () => processWrapper.run('git', [
            'config',
            '--get',
            'remote.origin.url',
          ], workingDirectory: d.path),
        ).thenAnswer((_) async => ProcessResult(1, 1, '', ''));

        mockPublishIsSuccessful(success: true, askBeforePublishing: false);
        publishedVersionValue = Version(1, 2, 3);
        mockPublishedVersion();

        messages.clear();
        await doPublish.exec(
          directory: d,
          ggLog: ggLog,
          askBeforePublishing: false,
          deleteFeatureBranch: false,
        );

        expect(messages.join('\n'), contains('✅ Tag 1.2.4 added.'));
      });

      test('warns and merges locally on an unsupported provider', () async {
        // The default remote stub points to git.example.com — no PR support.
        mockPublishIsSuccessful(success: true, askBeforePublishing: false);
        publishedVersionValue = Version(1, 2, 3);
        mockPublishedVersion();

        messages.clear();
        await doPublish.exec(
          directory: d,
          ggLog: ggLog,
          askBeforePublishing: false,
          deleteFeatureBranch: false,
        );

        final allMessages = messages.join('\n');
        expect(allMessages, contains('does not support the pull-request flow'));
        expect(allMessages, contains('✅ Tag 1.2.4 added.'));
      });

      test(
        '--no-pr forces the local merge flow on a supported remote',
        () async {
          // Azure remote — but --no-pr keeps the local merge + direct push.
          when(
            () => processWrapper.run('git', [
              'config',
              '--get',
              'remote.origin.url',
            ], workingDirectory: d.path),
          ).thenAnswer(
            (_) async => ProcessResult(
              0,
              0,
              'https://dev.azure.com/org/proj/_git/repo',
              '',
            ),
          );

          mockPublishIsSuccessful(success: true, askBeforePublishing: false);
          publishedVersionValue = Version(1, 2, 3);
          mockPublishedVersion();

          messages.clear();
          final runner = CommandRunner<void>('gg', 'gg')..addCommand(doPublish);
          await runner.run([
            'publish',
            '-i',
            d.path,
            '--no-pr',
            '--no-ask-before-publishing',
            '--no-delete-feature-branch',
          ]);

          // A pull-request flow would fail in this sandbox (no az/gh remote);
          // the successful tag proves the local merge ran.
          expect(messages.join('\n'), contains('✅ Tag 1.2.4 added.'));
        },
      );

      test('merges via a pull request on a protected (Azure) remote', () async {
        final mockDoMerge = MockDoMerge();
        when(
          () => mockDoMerge.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            automerge: any(named: 'automerge'),
            local: any(named: 'local'),
            message: any(named: 'message'),
            verbose: any(named: 'verbose'),
            viaPullRequest: any(named: 'viaPullRequest'),
            deleteSourceBranch: any(named: 'deleteSourceBranch'),
          ),
        ).thenAnswer((_) async {});

        // Azure remote → pull-request flow.
        when(
          () => processWrapper.run('git', [
            'config',
            '--get',
            'remote.origin.url',
          ], workingDirectory: d.path),
        ).thenAnswer(
          (_) async => ProcessResult(
            0,
            0,
            'https://dev.azure.com/org/proj/_git/repo',
            '',
          ),
        );

        mockPublishIsSuccessful(success: true, askBeforePublishing: false);
        publishedVersionValue = Version(1, 2, 3);
        mockPublishedVersion();

        final azurePublish = DoPublish(
          ggLog: ggLog,
          publish: publish,
          prepareNextVersion: PrepareNextVersion(
            ggLog: ggLog,
            publishedVersion: publishedVersion,
          ),
          canPublish: canPublish,
          isPublished: IsPublished(
            ggLog: ggLog,
            publishedVersion: publishedVersion,
          ),
          configurePublish: makeConfigurePublish(),
          publishedVersion: publishedVersion,
          processWrapper: processWrapper,
          localBranch: localBranch,
          confirmDeleteFeatureBranch: defaultConfirmDeleteFeatureBranch,
          doMerge: mockDoMerge,
        );

        messages.clear();
        await azurePublish.exec(
          directory: d,
          ggLog: ggLog,
          askBeforePublishing: false,
          deleteFeatureBranch: true,
        );

        // The merge went through the pull-request path, forwarding the
        // delete decision to the provider.
        verify(
          () => mockDoMerge.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            automerge: any(named: 'automerge'),
            local: any(named: 'local'),
            message: any(named: 'message'),
            verbose: any(named: 'verbose'),
            viaPullRequest: true,
            deleteSourceBranch: true,
          ),
        ).called(1);

        // The branch deletion runs here too — idempotent when the provider
        // already deleted the source branch on auto-complete.
        verify(
          () => processWrapper.run('git', [
            'push',
            'origin',
            '--delete',
            'feat_abc',
          ], workingDirectory: d.path),
        ).called(1);
      });
    });

    group('configure + resume', () {
      late File runtimeFile;

      setUp(() {
        runtimeFile = File(join(d.path, '.gg', '.gg-publish.json'));
      });

      void stubGit(List<String> args, {int exitCode = 0}) {
        when(
          () => processWrapper.run('git', args, workingDirectory: d.path),
        ).thenAnswer((_) async => ProcessResult(0, exitCode, '', ''));
      }

      AddVersionTag mockAddVersionTag() {
        final tag = _MockAddVersionTag();
        when(
          () => tag.exec(
            directory: any<Directory>(named: 'directory'),
            ggLog: any<GgLog>(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});
        return tag;
      }

      DoPublish makeResumePublish({
        AddVersionTag? addVersionTag,
        EditMessage? editMessage,
        ConfirmDeleteFeatureBranch? confirmDeleteFeatureBranch,
      }) => DoPublish(
        ggLog: ggLog,
        publish: publish,
        prepareNextVersion: PrepareNextVersion(
          ggLog: ggLog,
          publishedVersion: publishedVersion,
        ),
        canPublish: canPublish,
        isPublished: IsPublished(
          ggLog: ggLog,
          publishedVersion: publishedVersion,
        ),
        addVersionTag: addVersionTag ?? mockAddVersionTag(),
        configurePublish: makeConfigurePublish(
          editMessage:
              editMessage ??
              (_) async => fail('Editor must not open on a resumed run.'),
        ),
        publishedVersion: publishedVersion,
        processWrapper: processWrapper,
        localBranch: localBranch,
        confirmDeleteFeatureBranch:
            confirmDeleteFeatureBranch ?? defaultConfirmDeleteFeatureBranch,
        doMerge: noPubGetDoMerge(),
      );

      test('--continue without a saved run throws a clear error', () async {
        final runner = CommandRunner<void>('gg', 'gg')..addCommand(doPublish);
        await expectLater(
          () => runner.run(['publish', '-i', d.path, '--continue']),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Nothing to continue'),
            ),
          ),
        );
      });

      test('--continue rejects --config and --reconfigure', () async {
        Matcher throwsCombineError() => throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('cannot be combined'),
          ),
        );
        await expectLater(
          () => (CommandRunner<void>('gg', 'gg')..addCommand(doPublish)).run([
            'publish',
            '-i',
            d.path,
            '--continue',
            '--config',
            'x.json',
          ]),
          throwsCombineError(),
        );
        await expectLater(
          () =>
              (CommandRunner<void>(
                'gg',
                'gg',
              )..addCommand(makeResumePublish())).run([
                'publish',
                '-i',
                d.path,
                '--continue',
                '--reconfigure',
              ]),
          throwsCombineError(),
        );
      });

      test(
        'a plain re-run refuses a runtime file that holds progress',
        () async {
          runtimeFile.writeAsStringSync('''
{
  "version_increment": "patch",
  "merge_message": "m",
  "done_steps": ["prepare_version"]
}
''');
          await expectLater(
            () => doPublish.exec(directory: d, ggLog: ggLog),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'message',
                contains('unfinished publish left progress'),
              ),
            ),
          );
        },
      );

      test('reuses an existing config file without prompting', () async {
        mockPublishIsSuccessful(success: true, askBeforePublishing: false);
        runtimeFile.writeAsStringSync(
          '{"version_increment":"patch",'
          '"merge_message":"From runtime file"}',
        );

        final strictPublish = DoPublish(
          ggLog: ggLog,
          publish: publish,
          prepareNextVersion: PrepareNextVersion(
            ggLog: ggLog,
            publishedVersion: publishedVersion,
          ),
          canPublish: canPublish,
          isPublished: IsPublished(
            ggLog: ggLog,
            publishedVersion: publishedVersion,
          ),
          configurePublish: makeConfigurePublish(
            editMessage: (_) async =>
                fail('Editor must not open when the config file exists.'),
          ),
          publishedVersion: publishedVersion,
          processWrapper: processWrapper,
          localBranch: localBranch,
          confirmDeleteFeatureBranch: defaultConfirmDeleteFeatureBranch,
          doMerge: noPubGetDoMerge(),
        );

        await strictPublish.exec(
          directory: d,
          ggLog: ggLog,
          askBeforePublishing: false,
          deleteFeatureBranch: false,
        );

        final headMessage = await HeadMessage(
          ggLog: ggLog,
        ).get(directory: d, ggLog: ggLog);
        expect(headMessage, 'From runtime file');
        // The runtime file is removed after the successful publish.
        expect(runtimeFile.existsSync(), isFalse);
      });

      test('--continue resumes at the open tag step', () async {
        // prepare/registry/merge already done; HEAD still on feat_abc as
        // after a gg_multi keep-commits restore.
        runtimeFile.writeAsStringSync('''
{
  "version_increment": "patch",
  "merge_message": "m",
  "branch": "feat_abc",
  "done_steps": ["prepare_version", "publish_registry", "merge"]
}
''');
        stubGit(['rev-parse', '--verify', '--quiet', 'refs/heads/main']);
        stubGit(['checkout', 'main']);
        final tag = mockAddVersionTag();
        final resumePublish = makeResumePublish(addVersionTag: tag);

        final runner = CommandRunner<void>('gg', 'gg')
          ..addCommand(resumePublish);
        await runner.run([
          'publish',
          '-i',
          d.path,
          '--continue',
          '--no-delete-feature-branch',
        ]);

        final allMessages = messages.join('\n');
        expect(allMessages, contains('Resuming the unfinished publish'));
        expect(
          allMessages,
          contains('Checked out main to finish the resumed publish.'),
        );
        // The registry publish was skipped — the step was already done.
        verifyNever(
          () => publish.exec(
            directory: any<Directory>(named: 'directory'),
            ggLog: any<GgLog>(named: 'ggLog'),
            askBeforePublishing: any<bool>(named: 'askBeforePublishing'),
          ),
        );
        // The default branch was checked out and the tag added there.
        verify(
          () => processWrapper.run('git', [
            'checkout',
            'main',
          ], workingDirectory: d.path),
        ).called(1);
        verify(
          () => tag.exec(
            directory: any<Directory>(named: 'directory'),
            ggLog: any<GgLog>(named: 'ggLog'),
          ),
        ).called(1);
        expect(runtimeFile.existsSync(), isFalse);
      });

      test(
        'resume: true (multi flow) skips done steps without CLI flags',
        () async {
          runtimeFile.writeAsStringSync('''
{
  "version_increment": "patch",
  "merge_message": "m",
  "branch": "feat_abc",
  "delete_feature_branch": false,
  "done_steps": ["prepare_version"]
}
''');
          // The un-bumped version equals the registry version — the registry
          // safety net skips the publish step.
          publishedVersionValue = Version(1, 2, 3);
          mockPublishedVersion();

          // No deleteFeatureBranch parameter: with increment + message given
          // as parameters, the open delete decision comes from the runtime
          // file — no prompt.
          final resumePublish = makeResumePublish(
            confirmDeleteFeatureBranch: (_) =>
                fail('The stored decision applies — no prompt.'),
          );
          await resumePublish.exec(
            directory: d,
            ggLog: ggLog,
            resume: true,
            message: 'Resumed merge',
            versionIncrement: 'patch',
            askBeforePublishing: false,
          );

          expect(
            messages.join('\n'),
            contains('Resuming the unfinished publish'),
          );
          verifyNever(
            () => publish.exec(
              directory: any<Directory>(named: 'directory'),
              ggLog: any<GgLog>(named: 'ggLog'),
              askBeforePublishing: any<bool>(named: 'askBeforePublishing'),
            ),
          );
          // Explicit parameters win over the runtime file values.
          final headMessage = await HeadMessage(
            ggLog: ggLog,
          ).get(directory: d, ggLog: ggLog);
          expect(headMessage, 'Resumed merge');
          expect(runtimeFile.existsSync(), isFalse);
        },
      );

      test('the persisted branch wins over HEAD for the delete step', () async {
        runtimeFile.writeAsStringSync('''
{
  "version_increment": "patch",
  "merge_message": "m",
  "branch": "feat_other",
  "done_steps": ["prepare_version", "publish_registry", "merge"]
}
''');
        stubGit(['rev-parse', '--verify', '--quiet', 'refs/heads/main']);
        stubGit(['checkout', 'main']);
        stubGit(['push', 'origin', '--delete', 'feat_other']);

        final resumePublish = makeResumePublish();
        await resumePublish.exec(
          directory: d,
          ggLog: ggLog,
          resume: true,
          deleteFeatureBranch: true,
        );

        // The branch recorded at publish start is deleted — not the branch
        // HEAD happens to be on now.
        verify(
          () => processWrapper.run('git', [
            'push',
            'origin',
            '--delete',
            'feat_other',
          ], workingDirectory: d.path),
        ).called(1);
        verifyNever(
          () => processWrapper.run('git', [
            'push',
            'origin',
            '--delete',
            'feat_abc',
          ], workingDirectory: d.path),
        );
      });

      test(
        'a resume reuses the stored delete decision without a prompt',
        () async {
          runtimeFile.writeAsStringSync('''
{
  "version_increment": "patch",
  "merge_message": "m",
  "branch": "feat_other",
  "delete_feature_branch": true,
  "done_steps": ["prepare_version", "publish_registry", "merge"]
}
''');
          stubGit(['rev-parse', '--verify', '--quiet', 'refs/heads/main']);
          stubGit(['checkout', 'main']);
          stubGit(['push', 'origin', '--delete', 'feat_other']);

          final runner = CommandRunner<void>('gg', 'gg')
            ..addCommand(
              makeResumePublish(
                confirmDeleteFeatureBranch: (_) =>
                    fail('The stored decision applies — no prompt on resume.'),
              ),
            );
          await runner.run(['publish', '-i', d.path, '--continue']);

          verify(
            () => processWrapper.run('git', [
              'push',
              'origin',
              '--delete',
              'feat_other',
            ], workingDirectory: d.path),
          ).called(1);
        },
      );

      test(
        'a resumed delete tolerates an already-deleted remote branch',
        () async {
          // The delete re-runs on resume (a multi-flow resume may have
          // re-pushed the branch); a remote ref that is already gone must
          // not fail the run.
          runtimeFile.writeAsStringSync('''
{
  "version_increment": "patch",
  "merge_message": "m",
  "branch": "feat_other",
  "done_steps": ["prepare_version", "publish_registry", "merge"]
}
''');
          stubGit(['rev-parse', '--verify', '--quiet', 'refs/heads/main']);
          stubGit(['checkout', 'main']);
          when(
            () => processWrapper.run('git', [
              'push',
              'origin',
              '--delete',
              'feat_other',
            ], workingDirectory: d.path),
          ).thenAnswer(
            (_) async => ProcessResult(
              0,
              1,
              '',
              "error: unable to delete 'feat_other': "
                  'remote ref does not exist',
            ),
          );

          final resumePublish = makeResumePublish();
          await resumePublish.exec(
            directory: d,
            ggLog: ggLog,
            resume: true,
            deleteFeatureBranch: true,
          );

          expect(
            messages.join('\n'),
            contains('Remote feature branch feat_other was already deleted.'),
          );
        },
      );

      test(
        'a fresh run ignores the branch of a leftover config-only file',
        () async {
          // A run that failed before its first step (e.g. in canPublish)
          // leaves a config-only file with a recorded branch. A later fresh
          // publish of a DIFFERENT branch must not delete that stale branch.
          mockPublishIsSuccessful(success: true, askBeforePublishing: false);
          runtimeFile.writeAsStringSync('''
{
  "version_increment": "patch",
  "merge_message": "m",
  "branch": "feat_other"
}
''');

          final freshPublish = makeResumePublish(
            editMessage: (_) async =>
                fail('Editor must not open when the config file exists.'),
          );
          await freshPublish.exec(
            directory: d,
            ggLog: ggLog,
            askBeforePublishing: false,
            deleteFeatureBranch: true,
          );

          // HEAD's branch (feat_abc) is deleted — not the stale feat_other.
          verify(
            () => processWrapper.run('git', [
              'push',
              'origin',
              '--delete',
              'feat_abc',
            ], workingDirectory: d.path),
          ).called(1);
          verifyNever(
            () => processWrapper.run('git', [
              'push',
              'origin',
              '--delete',
              'feat_other',
            ], workingDirectory: d.path),
          );
        },
      );

      test(
        'a resume aborts when raw commits were added after the failure',
        () async {
          runtimeFile.writeAsStringSync('''
{
  "version_increment": "patch",
  "merge_message": "m",
  "branch": "feat_abc",
  "done_steps": ["prepare_version"]
}
''');
          // A raw git commit (not via gg do commit) invalidates the
          // hash-keyed doCommit marker.
          await addAndCommitSampleFile(
            d,
            fileName: 'sneaked_in.txt',
            content: 'unvalidated',
          );

          await expectLater(
            () => makeResumePublish().exec(
              directory: d,
              ggLog: ggLog,
              resume: true,
              deleteFeatureBranch: false,
            ),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'message',
                contains('The repository changed since the failed publish'),
              ),
            ),
          );
        },
      );

      group('default-branch checkout on a resumed merge', () {
        Future<void> writeMergedRuntimeFile() async {
          runtimeFile.writeAsStringSync('''
{
  "version_increment": "patch",
  "merge_message": "m",
  "branch": "feat_abc",
  "done_steps": ["prepare_version", "publish_registry", "merge"]
}
''');
        }

        test('falls back to master when main does not exist', () async {
          await writeMergedRuntimeFile();
          stubGit([
            'rev-parse',
            '--verify',
            '--quiet',
            'refs/heads/main',
          ], exitCode: 1);
          stubGit(['rev-parse', '--verify', '--quiet', 'refs/heads/master']);
          stubGit(['checkout', 'master']);

          await makeResumePublish().exec(
            directory: d,
            ggLog: ggLog,
            resume: true,
            deleteFeatureBranch: false,
          );

          verify(
            () => processWrapper.run('git', [
              'checkout',
              'master',
            ], workingDirectory: d.path),
          ).called(1);
        });

        test('does not check out when already on the default branch', () async {
          await writeMergedRuntimeFile();
          stubGit(['rev-parse', '--verify', '--quiet', 'refs/heads/main']);
          when(
            () => localBranch.get(
              directory: any(named: 'directory'),
              ggLog: any(named: 'ggLog'),
            ),
          ).thenAnswer((_) async => 'main');

          await makeResumePublish().exec(
            directory: d,
            ggLog: ggLog,
            resume: true,
            deleteFeatureBranch: false,
          );

          verifyNever(
            () => processWrapper.run('git', [
              'checkout',
              'main',
            ], workingDirectory: d.path),
          );
        });

        test('tolerates a repo without main and master', () async {
          await writeMergedRuntimeFile();
          stubGit([
            'rev-parse',
            '--verify',
            '--quiet',
            'refs/heads/main',
          ], exitCode: 1);
          stubGit([
            'rev-parse',
            '--verify',
            '--quiet',
            'refs/heads/master',
          ], exitCode: 1);

          await makeResumePublish().exec(
            directory: d,
            ggLog: ggLog,
            resume: true,
            deleteFeatureBranch: false,
          );

          expect(runtimeFile.existsSync(), isFalse);
        });

        test('throws when the checkout fails', () async {
          await writeMergedRuntimeFile();
          stubGit(['rev-parse', '--verify', '--quiet', 'refs/heads/main']);
          stubGit(['checkout', 'main'], exitCode: 1);

          await expectLater(
            () => makeResumePublish().exec(
              directory: d,
              ggLog: ggLog,
              resume: true,
              deleteFeatureBranch: false,
            ),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'message',
                contains('git checkout main failed'),
              ),
            ),
          );
        });
      });

      test(
        '--reconfigure discards config and progress and reconfigures',
        () async {
          mockPublishIsSuccessful(success: true, askBeforePublishing: false);
          runtimeFile.writeAsStringSync('''
{
  "version_increment": "patch",
  "merge_message": "stale",
  "done_steps": ["prepare_version"]
}
''');

          final reconfigurePublish = makeResumePublish(
            addVersionTag: AddVersionTag(ggLog: ggLog),
            editMessage: (_) async => 'Reconfigured',
          );
          final runner = CommandRunner<void>('gg', 'gg')
            ..addCommand(reconfigurePublish);
          await runner.run([
            'publish',
            '-i',
            d.path,
            '--reconfigure',
            '--no-ask-before-publishing',
            '--no-delete-feature-branch',
          ]);

          final headMessage = await HeadMessage(
            ggLog: ggLog,
          ).get(directory: d, ggLog: ggLog);
          expect(headMessage, 'Reconfigured');
          expect(runtimeFile.existsSync(), isFalse);
        },
      );
    });

    test('should have a code coverage of 100%', () {
      expect(
        DoPublish(
          ggLog: ggLog,
          configurePublish: makeConfigurePublish(),
          publishedVersion: publishedVersion,
          processWrapper: processWrapper,
          localBranch: localBranch,
          confirmDeleteFeatureBranch: defaultConfirmDeleteFeatureBranch,
        ),
        isNotNull,
      );
    });
  });
}

class MockGgProcessWrapper extends Mock implements GgProcessWrapper {}

class MockLocalBranch extends Mock implements LocalBranch {}

class _MockCommit extends Mock implements Commit {}

class _MockAddVersionTag extends Mock implements AddVersionTag {}
