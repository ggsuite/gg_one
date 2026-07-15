// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

/// Throws when stdin is not a terminal, so headless runs (CI, scripts,
/// pipes) fail fast with an actionable message instead of hanging forever
/// on an interactive prompt.
///
/// [what] names the prompt (e.g. `the merge message prompt`); [alternative]
/// tells the user how to supply the value non-interactively.
void throwWhenNotATerminal(String what, String alternative) {
  if (!stdin.hasTerminal) {
    throw Exception(
      'Cannot show $what: stdin is not a terminal. '
      'For headless runs, $alternative.',
    );
  }
}
