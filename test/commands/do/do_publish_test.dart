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
import 'package:gg_console_colors/gg_console_colors.dart';
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
  // without a resolved configuration. Uses the mocked version selector and a
  // non-interactive merge-message editor.
  DoConfigurePublish makeConfigurePublish({EditMessage? editMessage}) =>
      DoConfigurePublish(
        ggLog: ggLog,
        versionSelector: versionSelector,
        editMessage: editMessage ?? defaultEditMessage,
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
      '"canPublish":{"success":{"hash":$successHash}},'
      '"doPublish":{"success":{"hash":$successHash}}}',
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

    // Default: a non-Azure remote → local merge flow (no pull request).
    when(
      () => processWrapper.run('git', [
        'config',
        '--get',
        'remote.origin.url',
      ], workingDirectory: d.path),
    ).thenAnswer(
      (_) async =>
          ProcessResult(0, 0, 'https://github.com/inlavigo/gg.git', ''),
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
        group('and not publish', () {
          test('when publishing was already successful', () async {
            await DirectJson.writeFile(
              file: File(join(d.path, '.gg', '.gg.json')),
              path: 'doPublish/success/hash',
              value: successHash,
            );

            await doPublish.exec(directory: d, ggLog: ggLog);
            expect(
              messages,
              contains(yellow('Current state is already published.')),
            );
          });
        });
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

                        // Mock needing publish
                        await DirectJson.writeFile(
                          file: File(join(d.path, '.gg', '.gg.json')),
                          path: 'doPublish/success/hash',
                          value: needsChangeHash,
                        );

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

                        expect(
                          await DidPublish(
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

                      // Mock needing publish
                      await DirectJson.writeFile(
                        file: File(join(d.path, '.gg', '.gg.json')),
                        path: 'doPublish/success/hash',
                        value: needsChangeHash,
                      );

                      // Publish
                      await doPublish.exec(
                        directory: d,
                        ggLog: ggLog,
                        askBeforePublishing: true,
                        deleteFeatureBranch: false,
                      );

                      // Check
                      expect(
                        await DidPublish(
                          ggLog: ggLog,
                        ).get(directory: d, ggLog: ggLog),
                        isTrue,
                      );
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

                  // Mock needing publish
                  await DirectJson.writeFile(
                    file: File(join(d.path, '.gg', '.gg.json')),
                    path: 'doPublish/success/hash',
                    value: needsChangeHash,
                  );

                  // Publish
                  await doPublish.exec(
                    directory: d,
                    ggLog: ggLog,
                    askBeforePublishing: false,
                    deleteFeatureBranch: false,
                  );

                  // Check result
                  expect(
                    await DidPublish(
                      ggLog: ggLog,
                    ).get(directory: d, ggLog: ggLog),
                    isTrue,
                  );
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

            await DirectJson.writeFile(
              file: File(join(d.path, '.gg', '.gg.json')),
              path: 'doPublish/success/hash',
              value: needsChangeHash,
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

            expect(
              await DidPublish(ggLog: ggLog).get(directory: d, ggLog: ggLog),
              isTrue,
            );
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

              // Mock needing publish
              await DirectJson.writeFile(
                file: File(join(d.path, '.gg', '.gg.json')),
                path: 'doPublish/success/hash',
                value: needsChangeHash,
              );

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

              expect(
                await DidPublish(ggLog: ggLog).get(directory: d, ggLog: ggLog),
                isTrue,
              );
            });
          });

          test('passes a custom merge message '
              'to the final merge step', () async {
            const customMessage = 'My custom merge message';

            mockPublishIsSuccessful(success: true, askBeforePublishing: false);

            await DirectJson.writeFile(
              file: File(join(d.path, '.gg', '.gg.json')),
              path: 'doPublish/success/hash',
              value: needsChangeHash,
            );

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

            await DirectJson.writeFile(
              file: File(join(d.path, '.gg', '.gg.json')),
              path: 'doPublish/success/hash',
              value: needsChangeHash,
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

            await DirectJson.writeFile(
              file: File(join(d.path, '.gg', '.gg.json')),
              path: 'doPublish/success/hash',
              value: needsChangeHash,
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

            await DirectJson.writeFile(
              file: File(join(d.path, '.gg', '.gg.json')),
              path: 'doPublish/success/hash',
              value: needsChangeHash,
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

              await DirectJson.writeFile(
                file: File(join(d.path, '.gg', '.gg.json')),
                path: 'doPublish/success/hash',
                value: needsChangeHash,
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

              await DirectJson.writeFile(
                file: File(join(d.path, '.gg', '.gg.json')),
                path: 'doPublish/success/hash',
                value: needsChangeHash,
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

          test(
            'asks whether to delete the feature branch when not specified',
            () async {
              mockPublishIsSuccessful(
                success: true,
                askBeforePublishing: false,
              );

              await DirectJson.writeFile(
                file: File(join(d.path, '.gg', '.gg.json')),
                path: 'doPublish/success/hash',
                value: needsChangeHash,
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
                configurePublish: makeConfigurePublish(),
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

          test('uses CLI delete-feature-branch flag when provided', () async {
            mockPublishIsSuccessful(success: true, askBeforePublishing: false);

            await DirectJson.writeFile(
              file: File(join(d.path, '.gg', '.gg.json')),
              path: 'doPublish/success/hash',
              value: needsChangeHash,
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
            await DirectJson.writeFile(
              file: File(join(d.path, '.gg', '.gg.json')),
              path: 'doPublish/success/hash',
              value: needsChangeHash,
            );

            // Config sits outside the repo to keep the working tree clean.
            final cfgDir = await Directory.systemTemp.createTemp(
              'publish_config_',
            );
            final cfgPath = join(cfgDir.path, 'release.json');
            await File(cfgPath).writeAsString(
              '{"version_increment":"patch",'
              '"merge_message":"from .gg-publish.json"}',
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
              confirmDeleteFeatureBranch: (_) => false,
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
              '--no-delete-feature-branch',
            ]);

            // Reaching here proves the load+resolve path ran successfully.
            expect(
              await DidPublish(ggLog: ggLog).get(directory: d, ggLog: ggLog),
              isTrue,
            );

            cfgDir.deleteSync(recursive: true);
          });

          test('logs each executed command when --verbose is set', () async {
            mockPublishIsSuccessful(success: true, askBeforePublishing: false);

            await DirectJson.writeFile(
              file: File(join(d.path, '.gg', '.gg.json')),
              path: 'doPublish/success/hash',
              value: needsChangeHash,
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

              await DirectJson.writeFile(
                file: File(join(d.path, '.gg', '.gg.json')),
                path: 'doPublish/success/hash',
                value: needsChangeHash,
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

              await DirectJson.writeFile(
                file: File(join(d.path, '.gg', '.gg.json')),
                path: 'doPublish/success/hash',
                value: needsChangeHash,
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

              // Mock needing publish
              await DirectJson.writeFile(
                file: File(join(d.path, '.gg', '.gg.json')),
                path: 'doPublish/success/hash',
                value: needsChangeHash,
              );

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
              expect(
                await DidPublish(ggLog: ggLog).get(directory: d, ggLog: ggLog),
                isFalse,
              );
            });
          });
        });

        test('when deleting the feature branch fails', () async {
          mockPublishIsSuccessful(success: true, askBeforePublishing: false);

          await DirectJson.writeFile(
            file: File(join(d.path, '.gg', '.gg.json')),
            path: 'doPublish/success/hash',
            value: needsChangeHash,
          );

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

          await DirectJson.writeFile(
            file: File(join(d.path, '.gg', '.gg.json')),
            path: 'doPublish/success/hash',
            value: needsChangeHash,
          );

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

        await DirectJson.writeFile(
          file: File(join(d.path, '.gg', '.gg.json')),
          path: 'doPublish/success/hash',
          value: needsChangeHash,
        );

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

        await DirectJson.writeFile(
          file: File(join(d.path, '.gg', '.gg.json')),
          path: 'doPublish/success/hash',
          value: needsChangeHash,
        );

        messages.clear();
        await doPublish.exec(
          directory: d,
          ggLog: ggLog,
          askBeforePublishing: false,
          deleteFeatureBranch: false,
        );

        expect(messages.join('\n'), contains('✅ Tag 1.2.4 added.'));
      });

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

        await DirectJson.writeFile(
          file: File(join(d.path, '.gg', '.gg.json')),
          path: 'doPublish/success/hash',
          value: needsChangeHash,
        );

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
        // Delete requested, but the PR flow must skip it (the provider deletes
        // the source branch on auto-complete).
        await azurePublish.exec(
          directory: d,
          ggLog: ggLog,
          askBeforePublishing: false,
          deleteFeatureBranch: true,
        );

        // The merge went through the pull-request path.
        verify(
          () => mockDoMerge.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            automerge: any(named: 'automerge'),
            local: any(named: 'local'),
            message: any(named: 'message'),
            verbose: any(named: 'verbose'),
            viaPullRequest: true,
          ),
        ).called(1);

        // The direct main push / branch deletion were skipped.
        verifyNever(
          () => processWrapper.run('git', [
            'push',
            'origin',
            '--delete',
            'feat_abc',
          ], workingDirectory: d.path),
        );
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
        confirmDeleteFeatureBranch: defaultConfirmDeleteFeatureBranch,
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
        await DirectJson.writeFile(
          file: File(join(d.path, '.gg', '.gg.json')),
          path: 'doPublish/success/hash',
          value: needsChangeHash,
        );
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
  "done_steps": ["prepare_version"]
}
''');
          // The un-bumped version equals the registry version — the registry
          // safety net skips the publish step.
          publishedVersionValue = Version(1, 2, 3);
          mockPublishedVersion();

          final resumePublish = makeResumePublish();
          await resumePublish.exec(
            directory: d,
            ggLog: ggLog,
            resume: true,
            message: 'Resumed merge',
            versionIncrement: 'patch',
            askBeforePublishing: false,
            deleteFeatureBranch: false,
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
        'the delete_feature_branch step is not repeated on resume',
        () async {
          runtimeFile.writeAsStringSync('''
{
  "version_increment": "patch",
  "merge_message": "m",
  "branch": "feat_other",
  "done_steps":
    ["prepare_version", "publish_registry", "merge",
     "delete_feature_branch"]
}
''');
          stubGit(['rev-parse', '--verify', '--quiet', 'refs/heads/main']);
          stubGit(['checkout', 'main']);

          final resumePublish = makeResumePublish();
          await resumePublish.exec(
            directory: d,
            ggLog: ggLog,
            resume: true,
            deleteFeatureBranch: true,
          );

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
          await DirectJson.writeFile(
            file: File(join(d.path, '.gg', '.gg.json')),
            path: 'doPublish/success/hash',
            value: needsChangeHash,
          );
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
