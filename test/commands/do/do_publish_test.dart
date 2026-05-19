// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_direct_json/gg_direct_json.dart';
import 'package:gg_git/gg_git.dart';
import 'package:gg_git/gg_git_test_helpers.dart';
import 'package:gg_merge/gg_merge.dart' as gg_merge;
import 'package:gg_one/gg_one.dart';
import 'package:gg_process/gg_process.dart';
import 'package:gg_publish/gg_publish.dart';
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
      versionSelector: versionSelector,
      publishedVersion: publishedVersion,
      processWrapper: processWrapper,
      localBranch: localBranch,
      confirmDeleteFeatureBranch: defaultConfirmDeleteFeatureBranch,
      editMessage: defaultEditMessage,
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

                        // Was .gg/.gg.json updated in a way that didCommit,
                        // didPush and didPublish return true?
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
            test('when »publish_to: none« is found in pubspec.yaml', () async {
              doPublish = DoPublish(
                ggLog: ggLog,
                publish: publish,
                versionSelector: versionSelector,
                processWrapper: processWrapper,
                localBranch: localBranch,
                confirmDeleteFeatureBranch: defaultConfirmDeleteFeatureBranch,
                editMessage: defaultEditMessage,
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

              // Was .gg/.gg.json updated in a way that didCommit,
              // didPush and didPublish return true?
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
              versionSelector: versionSelector,
              publishedVersion: publishedVersion,
              processWrapper: processWrapper,
              localBranch: localBranch,
              confirmDeleteFeatureBranch: defaultConfirmDeleteFeatureBranch,
              editMessage: (message) async {
                initialMessage = message;
                return 'Edited merge message';
              },
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
              versionSelector: versionSelector,
              publishedVersion: publishedVersion,
              processWrapper: processWrapper,
              localBranch: localBranch,
              confirmDeleteFeatureBranch: defaultConfirmDeleteFeatureBranch,
              editMessage: (message) async {
                initialMessage = message;
                return 'Edited without ticket';
              },
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
              versionSelector: versionSelector,
              publishedVersion: publishedVersion,
              processWrapper: processWrapper,
              localBranch: localBranch,
              editMessage: (_) async {
                fail('Editor must not be opened when message is provided.');
              },
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
                versionSelector: versionSelector,
                publishedVersion: publishedVersion,
                processWrapper: processWrapper,
                localBranch: localBranch,
                editMessage: defaultEditMessage,
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
              versionSelector: versionSelector,
              publishedVersion: publishedVersion,
              processWrapper: processWrapper,
              localBranch: localBranch,
              editMessage: defaultEditMessage,
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
              versionSelector: versionSelector,
              publishedVersion: publishedVersion,
              processWrapper: processWrapper,
              localBranch: localBranch,
              editMessage: defaultEditMessage,
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
                versionSelector: versionSelector,
                publishedVersion: publishedVersion,
                processWrapper: processWrapper,
                localBranch: localBranch,
                editMessage: defaultEditMessage,
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
                versionSelector: versionSelector,
                publishedVersion: publishedVersion,
                processWrapper: processWrapper,
                localBranch: localBranch,
                editMessage: (_) async {
                  fail(
                    'Editor must not be opened when CLI message is provided.',
                  );
                },
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

    test('should have a code coverage of 100%', () {
      expect(
        DoPublish(
          ggLog: ggLog,
          versionSelector: versionSelector,
          publishedVersion: publishedVersion,
          processWrapper: processWrapper,
          localBranch: localBranch,
          confirmDeleteFeatureBranch: defaultConfirmDeleteFeatureBranch,
          editMessage: defaultEditMessage,
        ),
        isNotNull,
      );
    });
  });
}

class MockGgProcessWrapper extends Mock implements GgProcessWrapper {}

class MockLocalBranch extends Mock implements LocalBranch {}
