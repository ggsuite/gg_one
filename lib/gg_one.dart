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

// Can
export 'package:gg_one_commit/gg_one_commit.dart';
export 'src/commands/can.dart';
export 'src/commands/can/can_publish.dart';
// Checks
export 'package:gg_one_checks/gg_one_checks.dart';
// Did
export 'src/commands/did.dart';
export 'src/commands/did/did_publish.dart';
export 'src/commands/did/did_upgrade.dart';
// Do
export 'src/commands/do.dart';
export 'src/commands/do/create.dart';
export 'src/commands/do/do_publish.dart';
export 'src/commands/do/do_upgrade.dart';
// Info
export 'src/commands/info.dart';
export 'src/gg.dart';
// Tools
export 'package:gg_one_merge/gg_one_merge.dart';
export 'package:gg_one_publish_config/gg_one_publish_config.dart';
export 'package:gg_one_state/gg_one_state.dart';
export 'src/tools/add_git_only_version_tag.dart';
export 'src/tools/add_typescript_version_tag.dart';
export 'src/tools/workspace_folder_guard.dart';
