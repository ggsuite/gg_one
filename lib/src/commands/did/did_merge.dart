// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_one/src/tools/did_command.dart';

/// Was the merge successful?
class DidMerge extends DidCommand {
  /// Constructor
  DidMerge({
    required super.ggLog,
    super.name = 'merge',
    super.description = 'Was the merge successful?',
    super.shortDescription = 'Merge was successful',
    super.suggestion = 'Merge not yet successful. Please run »gg do merge«.',
    super.stateKey = 'doMerge',
  });
}

/// Mock for [DidMerge]
class MockDidMerge extends MockDidCommand implements DidMerge {}
