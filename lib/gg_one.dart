// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

library;

// Project-type detection and package-manager handling now live in gg_lang
// (the shared language catalog). Re-exported here so existing gg_one
// consumers keep importing them from gg_one.
export 'package:gg_lang/gg_lang.dart'
    show
        ProjectType,
        ProjectTypeX,
        detectProjectType,
        isBridgeProject,
        checkProjectType,
        lockFileFor,
        TypeScriptPackageManager,
        detectTypeScriptPackageManager;

// The implementation lives in the packages of the gg_one family. They are
// re-exported here so existing consumers keep importing everything from
// gg_one.
export 'package:gg_one_commit/gg_one_commit.dart';
export 'package:gg_one_core/gg_one_core.dart';
export 'package:gg_one_do_publish/gg_one_do_publish.dart';
export 'package:gg_one_merge/gg_one_merge.dart';

// The command groups wiring those packages into one command line.
export 'src/commands/can.dart';
export 'src/commands/did.dart';
export 'src/commands/did/did_upgrade.dart';
export 'src/commands/do.dart';
export 'src/commands/do/create.dart';
export 'src/commands/do/do_upgrade.dart';
export 'src/commands/info.dart';
export 'src/gg.dart';
