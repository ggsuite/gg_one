// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_git/gg_git_test_helpers.dart';
import 'package:gg_one/gg_one.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

/// Deterministic [InteractAdapter] returning queued indices and capturing
/// the option lists it is shown (to assert the version previews).
class _StubAdapter implements InteractAdapter {
  _StubAdapter(this._indices);
  final List<int> _indices;
  int _call = 0;
  final List<List<String>> capturedOptions = [];

  @override
  Future<int> choose({
    required String message,
    required List<String> options,
  }) async {
    capturedOptions.add(options);
    final index = _indices[_call % _indices.length];
    _call++;
    return index;
  }
}

void main() {
  final messages = <String>[];
  final ggLog = messages.add;
  late Directory d;
  final capturedInitials = <String>[];

  setUp(() async {
    messages.clear();
    capturedInitials.clear();
    d = await Directory.systemTemp.createTemp('configure_publish_');
    await initLocalGit(d);
    await enableEolLf(d);
    await addAndCommitSampleFile(
      d,
      fileName: 'pubspec.yaml',
      content: 'name: test\nversion: 1.2.3\n',
    );
  });

  tearDown(() async {
    await d.delete(recursive: true);
  });

  DoConfigurePublish makeCommand({
    List<int> increments = const [0],
    _StubAdapter? adapter,
    EditMessage? editMessage,
  }) => DoConfigurePublish(
    ggLog: ggLog,
    versionSelector: VersionSelector(
      adapter: adapter ?? _StubAdapter(increments),
    ),
    editMessage:
        editMessage ??
        (String initial) async {
          capturedInitials.add(initial);
          return initial;
        },
  );

  PublishConfig reload() => PublishConfig.load(
    configArg: DoConfigurePublish.configFileFor(d).path,
    fallbackDir: d.path,
  );

  group('DoConfigurePublish', () {
    test(
      'writes increment + message and gitignores the runtime file',
      () async {
        File(
          join(d.path, '.ticket'),
        ).writeAsStringSync('{"description": "Ticket desc"}');

        final config = await makeCommand(
          increments: [1],
        ).configure(directory: d, ggLog: ggLog);

        expect(config.versionIncrement, 'minor');
        expect(config.mergeMessage, 'Ticket desc');
        expect(capturedInitials, ['Ticket desc']);

        final reloaded = reload();
        expect(reloaded.versionIncrement, 'minor');
        expect(reloaded.mergeMessage, 'Ticket desc');

        // The runtime file was gitignored before it was written.
        final gitignore = File(join(d.path, '.gitignore')).readAsStringSync();
        expect(gitignore, contains('.gg/.gg-publish.json'));
        expect(messages.join('\n'), contains('Wrote publish configuration'));
      },
    );

    test('a preset merge message skips the message prompt', () async {
      final command = makeCommand(
        editMessage: (_) async =>
            fail('Editor must not open for a preset message.'),
      );

      final config = await command.configure(
        directory: d,
        ggLog: ggLog,
        mergeMessage: '  Preset msg  ',
      );

      expect(config.mergeMessage, 'Preset msg');
    });

    test('a preset increment skips the increment prompt', () async {
      final adapter = _StubAdapter([0]);
      final config = await makeCommand(adapter: adapter).configure(
        directory: d,
        ggLog: ggLog,
        versionIncrement: 'major',
        mergeMessage: 'msg',
      );

      expect(config.versionIncrement, 'major');
      expect(adapter.capturedOptions, isEmpty);
    });

    test('an empty edit falls back to the ticket description', () async {
      File(
        join(d.path, '.ticket'),
      ).writeAsStringSync('{"description": "Ticket desc"}');

      final config = await makeCommand(
        editMessage: (_) async => '   ',
      ).configure(directory: d, ggLog: ggLog);

      expect(config.mergeMessage, 'Ticket desc');
    });

    test('an empty edit without .ticket falls back to Publish <dir>', () async {
      final config = await makeCommand(
        editMessage: (_) async => '',
      ).configure(directory: d, ggLog: ggLog);

      expect(config.mergeMessage, 'Publish ${basename(d.path)}');
    });

    group('merge-message default from .ticket', () {
      test('empty when .ticket is malformed JSON (no crash)', () async {
        File(join(d.path, '.ticket')).writeAsStringSync('{"description":');
        await makeCommand().configure(directory: d, ggLog: ggLog);
        expect(capturedInitials, ['']);
      });

      test('empty when .ticket is not a JSON object', () async {
        File(join(d.path, '.ticket')).writeAsStringSync('[]');
        await makeCommand().configure(directory: d, ggLog: ggLog);
        expect(capturedInitials, ['']);
      });

      test('empty when the description is blank', () async {
        File(
          join(d.path, '.ticket'),
        ).writeAsStringSync('{"description": "   "}');
        await makeCommand().configure(directory: d, ggLog: ggLog);
        expect(capturedInitials, ['']);
      });
    });

    group('version preview baseline', () {
      test('uses the pubspec version when readable', () async {
        final adapter = _StubAdapter([0]);
        await makeCommand(
          adapter: adapter,
        ).configure(directory: d, ggLog: ggLog, mergeMessage: 'msg');
        expect(adapter.capturedOptions.first.first, contains('1.2.3'));
      });

      test('falls back to package.json for TypeScript repos', () async {
        File(join(d.path, 'pubspec.yaml')).deleteSync();
        File(
          join(d.path, 'package.json'),
        ).writeAsStringSync('{"name": "x", "version": "2.5.0"}');

        final adapter = _StubAdapter([0]);
        await makeCommand(
          adapter: adapter,
        ).configure(directory: d, ggLog: ggLog, mergeMessage: 'msg');
        expect(adapter.capturedOptions.first.first, contains('2.5.0'));
      });

      test('falls back to 0.0.0 without any manifest', () async {
        File(join(d.path, 'pubspec.yaml')).deleteSync();

        final adapter = _StubAdapter([0]);
        await makeCommand(
          adapter: adapter,
        ).configure(directory: d, ggLog: ggLog, mergeMessage: 'msg');
        expect(adapter.capturedOptions.first.first, contains('0.0.0'));
      });
    });

    test('refuses to clobber the progress of an unfinished publish', () async {
      final file = DoConfigurePublish.configFileFor(d)
        ..createSync(recursive: true);
      file.writeAsStringSync('''
{
  "version_increment": "patch",
  "merge_message": "m",
  "done_steps": ["prepare_version", "publish_registry"]
}
''');

      await expectLater(
        () => makeCommand().configure(directory: d, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('unfinished publish left progress'),
          ),
        ),
      );
      // The file is untouched — the progress survives.
      final reloaded = reload();
      expect(reloaded.doneSteps, ['prepare_version', 'publish_registry']);
    });

    test('overwrites a progress-free config file without complaint', () async {
      final file = DoConfigurePublish.configFileFor(d)
        ..createSync(recursive: true);
      file.writeAsStringSync(
        '{"version_increment":"patch","merge_message":"old"}',
      );

      final config = await makeCommand().configure(
        directory: d,
        ggLog: ggLog,
        versionIncrement: 'minor',
        mergeMessage: 'new',
      );

      expect(config.mergeMessage, 'new');
      expect(reload().mergeMessage, 'new');
    });

    test('CLI run resolves the directory and honours -m', () async {
      final runner = CommandRunner<void>('gg', 'gg')
        ..addCommand(makeCommand(increments: [2]));

      await runner.run([
        'configure-publish',
        '-i',
        d.path,
        '-m',
        'CLI message',
      ]);

      final reloaded = reload();
      expect(reloaded.versionIncrement, 'major');
      expect(reloaded.mergeMessage, 'CLI message');
    });
  });
}
