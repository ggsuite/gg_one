// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_git/gg_git.dart' as gg_git;
import 'package:gg_log/gg_log.dart';

/// Checks out the branch belonging to a ticket in the current repository.
///
/// `gg do checkout <ticket>` fetches first (via gg_git) so a branch that only
/// lives on the remote can be checked out as a tracking branch, then switches
/// to it.
class DoCheckout extends DirCommand<void> {
  /// Constructor
  DoCheckout({
    required super.ggLog,
    super.name = 'checkout',
    super.description = 'Check out the branch belonging to a ticket.',
    gg_git.Fetch? fetch,
    gg_git.Checkout? checkout,
  }) : _fetch = fetch ?? gg_git.Fetch(ggLog: ggLog),
       _checkout = checkout ?? gg_git.Checkout(ggLog: ggLog);

  final gg_git.Fetch _fetch;
  final gg_git.Checkout _checkout;

  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
    String? branch,
  }) => get(directory: directory, ggLog: ggLog, branch: branch);

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    String? branch,
  }) async {
    branch ??= _branchFromArgs;

    if (branch.isEmpty) {
      throw UsageException('Missing ticket/branch name.', usage);
    }

    // Fetch first so a branch that only exists on the remote can be checked
    // out as a tracking branch.
    await _fetch.get(directory: directory, ggLog: ggLog);
    await _checkout.get(directory: directory, ggLog: ggLog, branch: branch);

    ggLog(green('Checked out $branch.'));
  }

  String get _branchFromArgs {
    final rest = argResults?.rest ?? const <String>[];
    return rest.isEmpty ? '' : rest.first;
  }
}

/// Mock for [DoCheckout].
class MockDoCheckout extends MockDirCommand<void> implements DoCheckout {}
