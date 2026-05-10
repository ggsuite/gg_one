# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

`gg_one` is a Dart CLI tool that streamlines developer workflows with pre-commit checks: code analysis, formatting, test execution with 100% coverage enforcement, and git workflow automation (commit, push, merge, publish).

## Commands

```bash
# Run all checks (analysis, format, tests)
dart run gg_one all

# Run tests
dart test                                              # all tests
dart test test/commands/can/can_commit_test.dart       # single file
dart test -n "pattern"                                 # by name pattern

# Individual checks
dart analyze
dart format .
```

## Architecture

Commands are organized into five top-level groups, each in `lib/src/commands/`:

- **`check/`** — static verification: `analyze`, `format`, `pana`
- **`can/`** — readiness checks before an action: `can_commit`, `can_push`, `can_merge`, `can_publish`, `can_upgrade`, `can_checkout`
- **`did/`** — historical checks (was something done?): `did_commit`, `did_push`, `did_merge`, `did_publish`, `did_upgrade`
- **`do/`** — actions that execute with validation: `do_commit`, `do_push`, `do_merge`, `do_publish`, `do_upgrade`, `do_maintain`, `create/`
- **`info/`** — informational queries

All commands extend `DirCommand<T>` from `gg_args`. The primary logic lives in `get()`, and `exec()` simply delegates to it. `ggLog` (a `GgLog` function alias) is constructor-injected everywhere for testability and output capture.

### State caching (`GgState`)

`lib/src/tools/gg_state.dart` manages the `.gg/.gg.json` file. Each successful check stores a hash of the working-tree state so subsequent runs can skip re-running checks when nothing has changed. When only `.gg/.gg.json` changed, it is auto-amended into the last commit (or committed as a new commit if already pushed).

### `CommandCluster`

Used for commands that aggregate multiple sub-checks. For example, `CanCommit` (in `can/`) runs `analyze`, `format`, and `tests` as a cluster, short-circuiting on the first failure.

## Testing Conventions

- 100% code coverage is required. Exempt lines with `// coverage:ignore-line` or `// coverage:ignore-start` / `// coverage:ignore-end`.
- Each implementation file must have a corresponding `_test.dart` in the mirrored path under `test/`.
- Mock classes are defined at the bottom of the **same file** as the class they mock (e.g. `MockDoCommit` in `do_commit.dart`), using `mocktail` and extending `MockDirCommand<T>`.
- Tests use `gg_git_test_helpers` to set up temporary git repos and `gg_capture_print` to assert on log output.
