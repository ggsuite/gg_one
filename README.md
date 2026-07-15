# gg_one

gg_one is a Dart package designed to streamline your development workflow by
offering a suite of pre-commit checks. These include code analysis, linting,
testing, and coverage verification, all complemented by highly optimized and
colorized error messages.

## Key Features

- ✅ **Precise Colorized Error Messages**: Get detailed feedback with error messages that are both precise and easy to understand, enhanced with color for better readability.
- ✅ **Optimized for VSCode**: Error messages are tailored for display in Visual Studio Code, ensuring a seamless integration into your development environment.
- ✅ **Enforces 100% Code Coverage**: Achieve and maintain high-quality code with enforced 100% test coverage for your codebase.
- ✅ **GitHub Action Integration**: Easily integrate gg_one with GitHub Actions to automate your testing workflow directly within GitHub.

## Preparation

### Install required tools

- `dart global activate pana`

### Create a New Library Project

```bash
dart create -t package hello_world
cd hello_world
```

### Add gg_one as a Development Dependency

Enhance your project with gg_one by adding it as a development dependency:

```bash
dart pub add --dev gg_one
```

### Discover gg_one Commands

Learn about the available commands and their applications:

```bash
dart pub run gg_one -h
```

### Execute All Tests and Checks

```bash
dart run gg_one all
```

### Fix the issues

Address issues identified by gg_one, aiming for a clean, error-free codebase..

## Ensure Comprehensive Code Coverage

gg_one demands excellence in testing:

- **Achieve 100% Code Coverage**: Mandatory complete test coverage for all code.
- **Review Short and Precise Coverage Reports**: Analyze uncovered lines and their corresponding tests.
- **Maintain Mandatory Test Files**: Ensure each implementation file has a dedicated test file achieving 100% coverage.

Exclude lines from code that should be excluded from code coverage:

```dart
// coverage:ignore-line
// coverage:ignore-start
// coverage:ignore-end
```

## Set Up GitHub Action for Automated Checks

Automate your testing process by setting up the gg_one GitHub Action, like here:

<https://github.com/ggsuite/gg_one/blob/main/.github/workflows/pipeline.yaml>

## Publish a single package with `gg one do publish`

`gg one do publish` walks a single repo through the publish pipeline:
`can publish` → version bump → CHANGELOG release → publish to pub.dev
(skipped when `publish_to: none` is set in `pubspec.yaml`) → merge
feature branch into `main` → push → tag.

All interactive decisions are made **up front**: when the command is
started without a resolved configuration it runs
`gg one do configure-publish`, which asks for the version increment
(`patch` / `minor` / `major`) and the merge message and writes them to
`<repo>/.gg/.gg-publish.json`. Pass `-m <message>` to skip the
merge-message prompt. You can also run `gg one do configure-publish`
on its own to prepare the file ahead of time. The file is gitignored
automatically (the `.gitignore` entry is appended and committed once
per repo).

### Resuming a failed publish

While the publish runs, its per-step progress (`done_steps`) is
recorded in the same `.gg/.gg-publish.json`; the file is deleted after
a fully successful publish. If a step fails partway through — even the
final version tag — fix the cause and resume with:

```bash
gg one do publish --continue
```

Already-completed steps are skipped; the idempotent pushes always
re-run. A leftover progress file makes a plain re-run refuse until you
choose `--continue` (resume) or `--reconfigure` (discard the config and
progress and be asked again).

For scripted releases and CI you can predeclare increment + message via
a JSON config file instead:

```bash
gg one do publish --config .gg-publish.json
```

### `.gg-publish.json` schema (single-repo)

`gg one` reads the **top-level** fields and ignores `repos`:

```jsonc
{
  "version_increment": "patch",                // "patch" | "minor" | "major"
  "merge_message": "Release: API cleanup"
}
```

Both fields are mandatory when `--config` is given — a missing field
causes a `FormatException` instead of silently dropping back to a
prompt.

### Where the config is looked up

Resolution order:

1. `<configArg>` as given (relative to the current directory, or an
   absolute path).
2. `<repo>/.gg/<configArg>` — handy for keeping per-package release
   defaults under version control inside the package itself.

### Example

```bash
cd my_package
cat .gg/release.json
# {
#   "version_increment": "minor",
#   "merge_message": "feat: add user-facing settings API"
# }

gg one do publish --config release.json   # finds it under .gg/
```

The same `.gg-publish.json` **schema** is shared with `gg multi do publish`
and carries two kinds of runtime markers, one per level:

- **Ticket level** (`gg multi do publish`): a per-repo `status` field
  (`pending` / `published` / `failed`) inside `repos.<name>` — which
  repos are already done.
- **Repo level** (`gg one do publish`): a top-level `done_steps` list
  (`prepare_version`, `publish_registry`, `merge`,
  `delete_feature_branch`, `tag`) plus the feature `branch` — which
  steps within one repo are already done.

Each level only reads its own markers. `PublishConfig` (in
`lib/src/tools/publish_config.dart`) also serializes back out
(`toJson` / `save`), so the file can be generated as well as read.

Note the two entry points read *different* config fields: single-repo
`--config` uses the **top-level** `version_increment` / `merge_message`
and ignores `repos`, whereas a file produced by
`gg multi do configure-publish` puts every value in per-repo
`repos.<name>` blocks with no top-level defaults. Such a generated file
therefore drives `gg multi do publish` but is **not** directly
consumable by single-repo `gg one do publish --config` — add top-level
fields if you want to reuse it for a single repo.
See the [`gg_multi` README](../gg_multi/README.md) for the multi-repo
form.

## Contributions

Report your errors and contributions to <https://github.com/ggsuite/gg_one>.

## History

`gg_one` is the successor of `gg`. The previous history (up to and including
commit `9141ef54f5edac470d119a39285813299143898f`) lives at
<https://github.com/ggsuite/gg>.
