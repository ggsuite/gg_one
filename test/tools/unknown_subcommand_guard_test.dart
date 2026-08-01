// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_one/gg_one.dart';
import 'package:test/test.dart';

void main() {
  final gg = Gg(ggLog: (_) {});

  String? error(List<String> args) =>
      unknownSubcommandError(command: gg, args: args);

  group('unknownSubcommandError(command, args)', () {
    group('returns an error', () {
      test('when the top level command does not exist', () {
        expect(
          error(['xyz']),
          startsWith('Could not find a subcommand named "xyz" for "gg_one".'),
        );
      });

      test('when a subcommand does not exist', () {
        expect(
          error(['do', 'xyz']),
          startsWith(
            'Could not find a subcommand named "xyz" for "gg_one do".',
          ),
        );
      });

      test('when a subcommand does not exist and »-h« is given', () {
        // The args package prints the usage of »do« in this case. See the
        // documentation of unknownSubcommandError.
        expect(
          error(['do', 'xyz', '-h']),
          startsWith(
            'Could not find a subcommand named "xyz" for "gg_one do".',
          ),
        );
      });

      test('when a sub-subcommand does not exist', () {
        expect(
          error(['do', 'create', 'xyz', '--help']),
          startsWith(
            'Could not find a subcommand named "xyz" for "gg_one do create".',
          ),
        );
      });

      test('when the command name is written out', () {
        expect(
          error(['gg_one', 'do', 'xyz']),
          startsWith(
            'Could not find a subcommand named "xyz" for "gg_one do".',
          ),
        );
      });

      test('listing the available subcommands in alphabetical order', () {
        expect(
          error(['do', 'xyz']),
          endsWith(
            'Available subcommands: checkout, commit, configure-publish, '
            'create, maintain, publish, push, upgrade',
          ),
        );
      });
    });

    group('returns null', () {
      test('when no arguments are given', () {
        expect(error([]), isNull);
      });

      test('when only flags are given', () {
        expect(error(['-h']), isNull);
      });

      test('when the whole command exists', () {
        expect(error(['do', 'commit']), isNull);
        expect(error(['do', 'create', 'ticket']), isNull);
      });

      test('when a command exists and »-h« is given', () {
        expect(error(['do', '-h']), isNull);
        expect(error(['do', 'commit', '--help']), isNull);
      });

      test('for the positional arguments of a leaf command', () {
        expect(error(['do', 'create', 'ticket', '69']), isNull);
        expect(error(['do', 'checkout', 'xyz']), isNull);
      });

      test('for values of an option written »--option value«', () {
        expect(error(['do', 'commit', '--message', 'publish']), isNull);
      });

      test('for values of an option written »--option=value«', () {
        expect(error(['do', 'commit', '--message=publish']), isNull);
      });

      test('for values of an abbreviated option', () {
        expect(error(['do', 'commit', '-m', 'publish']), isNull);
      });

      test('for values following an abbreviation cluster', () {
        // »-vm publish«: -v is a flag, -m takes the value.
        expect(error(['do', 'commit', '-vm', 'publish']), isNull);

        // »-mv publish«: -m ends the cluster, »v« is part of its value.
        expect(error(['do', 'commit', '-mv', 'publish']), isNull);
      });

      test('for negated flags', () {
        expect(error(['do', 'publish', '--no-pr']), isNull);
      });

      test('for unknown options', () {
        expect(error(['do', 'commit', '--unknown']), isNull);
      });

      test('for everything behind »--«', () {
        expect(error(['do', 'commit', '--', 'xyz']), isNull);
      });
    });
  });
}
