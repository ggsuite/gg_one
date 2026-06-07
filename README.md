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
`can publish` → version bump → CHANGELOG release → merge feature branch
into `main` → push → publish to pub.dev (skipped when
`publish_to: none` is set in `pubspec.yaml`).

By default the command is interactive: it asks for a merge message and
which part of the version to bump (`patch` / `minor` / `major`). For
scripted releases and CI you can predeclare both via a JSON config
file:

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

The same `.gg-publish.json` schema is shared with `gg multi do publish`,
which additionally honours a per-repo `repos.<name>` override block.
See the [`gg_multi` README](../gg_multi/README.md) for the multi-repo
form.

## Contributions

Report your errors and contributions to <https://github.com/ggsuite/gg_one>.

## History

`gg_one` is the successor of `gg`. The previous history (up to and including
commit `9141ef54f5edac470d119a39285813299143898f`) lives at
<https://github.com/ggsuite/gg>.
