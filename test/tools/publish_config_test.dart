// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_one/gg_one.dart';
import 'package:gg_publish/gg_publish.dart' show VersionIncrement;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('PublishConfig', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('gg_publish_cfg_');
    });
    tearDown(() async => tmp.delete(recursive: true));

    Future<File> writeConfig(String name, String body) async {
      final f = File(p.join(tmp.path, name));
      await f.writeAsString(body);
      return f;
    }

    group('load() — path resolution', () {
      test('uses the as-given path first', () async {
        final f = await writeConfig('release.json', '''
{
  "version_increment": "patch",
  "merge_message": "from CWD"
}
''');
        final cfg = PublishConfig.load(
          configArg: f.path,
          fallbackDir: tmp.path,
        );
        expect(cfg.versionIncrement, 'patch');
        expect(cfg.mergeMessage, 'from CWD');
      });

      test('falls back to <fallbackDir>/<configArg>', () async {
        await writeConfig('release.json', '''
{
  "version_increment": "minor",
  "merge_message": "from fallback"
}
''');
        final cfg = PublishConfig.load(
          configArg: 'release.json',
          fallbackDir: tmp.path,
        );
        expect(cfg.versionIncrement, 'minor');
        expect(cfg.mergeMessage, 'from fallback');
      });

      test('throws FileSystemException when nothing is found', () {
        expect(
          () => PublishConfig.load(
            configArg: 'missing.json',
            fallbackDir: tmp.path,
          ),
          throwsA(isA<FileSystemException>()),
        );
      });
    });

    group('load() — schema validation', () {
      test('rejects non-JSON content', () async {
        await writeConfig('release.json', 'not a json');
        expect(
          () => PublishConfig.load(
            configArg: 'release.json',
            fallbackDir: tmp.path,
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('not valid JSON'),
            ),
          ),
        );
      });

      test('rejects a non-object top-level value', () async {
        await writeConfig('release.json', '["array"]');
        expect(
          () => PublishConfig.load(
            configArg: 'release.json',
            fallbackDir: tmp.path,
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('JSON object at the top level'),
            ),
          ),
        );
      });

      test(
        'rejects an unknown version_increment with an enumerating error',
        () async {
          await writeConfig('release.json', '''
{
  "version_increment": "huge",
  "merge_message": "x"
}
''');
          expect(
            () => PublishConfig.load(
              configArg: 'release.json',
              fallbackDir: tmp.path,
            ),
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                allOf(
                  contains('version_increment'),
                  contains('patch'),
                  contains('minor'),
                  contains('major'),
                ),
              ),
            ),
          );
        },
      );

      test('rejects an empty merge_message', () async {
        await writeConfig('release.json', '''
{
  "version_increment": "patch",
  "merge_message": ""
}
''');
        expect(
          () => PublishConfig.load(
            configArg: 'release.json',
            fallbackDir: tmp.path,
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('"merge_message" must not be empty'),
            ),
          ),
        );
      });

      test('rejects a non-string merge_message', () async {
        await writeConfig('release.json', '''
{
  "version_increment": "patch",
  "merge_message": 42
}
''');
        expect(
          () => PublishConfig.load(
            configArg: 'release.json',
            fallbackDir: tmp.path,
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('"merge_message" must be a string'),
            ),
          ),
        );
      });

      test('rejects a non-object repos block', () async {
        await writeConfig('release.json', '''
{
  "version_increment": "patch",
  "merge_message": "x",
  "repos": []
}
''');
        expect(
          () => PublishConfig.load(
            configArg: 'release.json',
            fallbackDir: tmp.path,
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('"repos" must be a JSON object'),
            ),
          ),
        );
      });

      test('rejects a non-object repos.<name> entry', () async {
        await writeConfig('release.json', '''
{
  "version_increment": "patch",
  "merge_message": "x",
  "repos": { "foo": "bar" }
}
''');
        expect(
          () => PublishConfig.load(
            configArg: 'release.json',
            fallbackDir: tmp.path,
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('repos.foo must be a JSON object'),
            ),
          ),
        );
      });

      test('rejects an unknown version_increment in a repos entry', () async {
        await writeConfig('release.json', '''
{
  "version_increment": "patch",
  "merge_message": "x",
  "repos": {
    "foo": { "version_increment": "tiny" }
  }
}
''');
        expect(
          () => PublishConfig.load(
            configArg: 'release.json',
            fallbackDir: tmp.path,
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('repos.foo'),
            ),
          ),
        );
      });
    });

    group('resolveSingle()', () {
      test('returns the top-level values when both are present', () {
        final cfg = PublishConfig(
          versionIncrement: 'minor',
          mergeMessage: 'release X',
        );
        final r = cfg.resolveSingle(configPath: 'release.json');
        expect(r.versionIncrement, 'minor');
        expect(r.mergeMessage, 'release X');
      });

      test('hard errors when version_increment is missing', () {
        final cfg = PublishConfig(mergeMessage: 'release X');
        expect(
          () => cfg.resolveSingle(configPath: 'release.json'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('version_increment'),
            ),
          ),
        );
      });

      test('hard errors when merge_message is missing', () {
        final cfg = PublishConfig(versionIncrement: 'minor');
        expect(
          () => cfg.resolveSingle(configPath: 'release.json'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('merge_message'),
            ),
          ),
        );
      });

      test('enumerates all missing fields in a single error', () {
        final cfg = PublishConfig();
        expect(
          () => cfg.resolveSingle(configPath: 'release.json'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              allOf(contains('version_increment'), contains('merge_message')),
            ),
          ),
        );
      });
    });

    group('forRepo()', () {
      test('per-repo override beats the top-level default', () {
        final cfg = PublishConfig(
          versionIncrement: 'patch',
          mergeMessage: 'default',
          repos: {
            'app_core': RepoOverride(
              versionIncrement: 'minor',
              mergeMessage: 'custom',
            ),
          },
        );
        final r = cfg.forRepo(repoName: 'app_core', configPath: 'release.json');
        expect(r.versionIncrement, 'minor');
        expect(r.mergeMessage, 'custom');
      });

      test('falls back to top-level when override only sets one field', () {
        final cfg = PublishConfig(
          versionIncrement: 'patch',
          mergeMessage: 'default',
          repos: {'app_core': RepoOverride(mergeMessage: 'only message')},
        );
        final r = cfg.forRepo(repoName: 'app_core', configPath: 'release.json');
        expect(r.versionIncrement, 'patch');
        expect(r.mergeMessage, 'only message');
      });

      test('uses top-level defaults when no override is registered', () {
        final cfg = PublishConfig(
          versionIncrement: 'patch',
          mergeMessage: 'default',
        );
        final r = cfg.forRepo(repoName: 'unknown', configPath: 'release.json');
        expect(r.versionIncrement, 'patch');
        expect(r.mergeMessage, 'default');
      });

      test(
        'hard errors when neither override nor top-level supplies a value',
        () {
          final cfg = PublishConfig(
            mergeMessage: 'default',
            repos: {'app_core': RepoOverride()},
          );
          expect(
            () => cfg.forRepo(repoName: 'app_core', configPath: 'release.json'),
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                allOf(
                  contains('version_increment'),
                  contains('repos.app_core'),
                ),
              ),
            ),
          );
        },
      );
    });

    group('parseVersionIncrement()', () {
      test('maps the three valid strings to VersionIncrement', () {
        expect(parseVersionIncrement('patch'), VersionIncrement.patch);
        expect(parseVersionIncrement('minor'), VersionIncrement.minor);
        expect(parseVersionIncrement('major'), VersionIncrement.major);
      });

      test('throws ArgumentError for an unknown increment', () {
        expect(
          () => parseVersionIncrement('huge'),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    test('allowedVersionIncrements covers exactly patch/minor/major', () {
      expect(allowedVersionIncrements, equals({'patch', 'minor', 'major'}));
    });
  });
}
