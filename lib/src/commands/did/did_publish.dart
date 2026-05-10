// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_one/src/tools/did_command.dart';

/// Everything is published to pub.dev or git?
class DidPublish extends DidCommand {
  /// Constructor
  DidPublish({
    super.name = 'publish',
    super.description = 'Everything is published to pub.dev or git?',
    super.shortDescription = 'Package is published',
    super.suggestion = 'Not yet published. Please run »gg do publish«.',
    super.stateKey = 'doPublish',
    required super.ggLog,
  });
}

/// Mock for [DidPublish]
class MockDidPublish extends MockDidCommand implements DidPublish {}
