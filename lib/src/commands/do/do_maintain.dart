// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_one/gg_one.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_status_printer/gg_status_printer.dart';

/// Upgrades all dependencies
class DoMaintain extends DirCommand<void> {
  /// Constructor
  DoMaintain({
    required super.ggLog,
    super.name = 'maintain',
    super.description = 'Upgrades the package dependencies.',
    GgState? state,
    DoUpgrade? doUpgrade,
  }) : _doUpgrade = doUpgrade ?? DoUpgrade(ggLog: ggLog) {
    _addParam();
  }

  // ...........................................................................
  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
    bool? majorVersions,
  }) {
    return get(
      directory: directory,
      ggLog: ggLog,
      majorVersions: majorVersions,
    );
  }

  // ...........................................................................
  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    bool? majorVersions,
  }) async {
    majorVersions ??= _majorVersionsFromArgs;

    final messages = <String>[];

    // Run »gg do upgrade«
    await GgStatusPrinter<void>(
      ggLog: ggLog,
      message: 'Upgrading dependencies',
    ).logTask(
      task: () => _doUpgrade.get(
        directory: directory,
        ggLog: messages.add,
        majorVersions: majorVersions,
      ),
      success: (result) => true,
    );
  }

  /// The key used to save the state of the command
  final String stateKey = 'doMaintain';

  // ######################
  // Private
  // ######################

  // ...........................................................................

  final DoUpgrade _doUpgrade;

  // ...........................................................................
  void _addParam() {
    argParser.addFlag(
      'major-versions',
      abbr: 'm',
      help:
          'Upgrades packages to their latest resolvable versions, '
          'and updates pubspec.yaml.',
      defaultsTo: false,
      negatable: false,
    );
  }

  // ...........................................................................
  bool get _majorVersionsFromArgs {
    final majorVersions = argResults?['major-versions'] as bool? ?? false;
    return majorVersions;
  }
}

/// Mock for [DoMaintain].
class MockDoMaintain extends MockDirCommand<void> implements DoMaintain {}
