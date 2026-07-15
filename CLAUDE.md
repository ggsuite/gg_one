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

- **`check/`** — static verification: `analyze`, `format`, `pana`, `package_json_scripts` (TypeScript npm scripts), `npm_logged_in` (npm auth before publish)
- **`can/`** — readiness checks before an action: `can_commit`, `can_push`, `can_merge`, `can_publish`, `can_upgrade`, `can_checkout`
- **`did/`** — historical checks (was something done?): `did_commit`, `did_push`, `did_merge`, `did_publish`, `did_upgrade`
- **`do/`** — actions that execute with validation: `do_commit`, `do_push`, `do_merge`, `do_publish`, `do_configure_publish`, `do_upgrade`, `do_maintain`, `do_checkout`, `create/`
  - `do_checkout <ticket>` fetches and checks out a ticket's branch (delegating to `gg_git`'s `Fetch` + `Checkout`).
  - `do_merge` drops the `.gg/.ticket.json` ticket marker (and its `.gitignore` whitelist) before merging, so it never lands on the main branch.
  - `do_merge`/`do_publish` detect a protected main branch (Azure DevOps `origin` → `TF402455`) and, instead of a local merge + direct push to main, merge through an auto-complete pull request (`gg_merge`'s `MergeGit`) and wait for it (`gg_merge`'s `WaitForMerge`, unbounded poll). Afterwards only tags are pushed (`git push --tags` is not blocked by the branch policy). Non-protected remotes keep the local-merge flow.
- **`info/`** — informational queries

### Publish flow (`do_publish` + `do_configure_publish`)

`do publish` resolves all interactive input **up front**: explicit parameters (the gg_multi flow) > `--config <path>` > an existing `<repo>/.gg/.gg-publish.json` > an automatic interactive `do configure-publish` (which writes that file; `-m` presets the merge message and skips its prompt). While the publish runs, per-step progress is recorded in the same `.gg/.gg-publish.json` (`done_steps`: `prepare_version`, `publish_registry`, `merge`, `delete_feature_branch`, `tag` — the three pushes are idempotent and always re-run). The file also records the feature `branch`, because a resumed run may find HEAD on the default branch already. On full success the file is deleted.

Resume semantics: a leftover file with `done_steps` makes a plain `do publish` **refuse** (resume with `--continue`, discard with `--reconfigure`); `--continue` (or the programmatic `resume: true` that `gg_multi do publish --continue` forwards) skips the done steps, skips `can publish` (the checks would fail on a half-published repo) and — when the merge step is already done — checks out the default branch so push/tag target the release commit. `EnsurePublishConfigIgnored` (in `tools/`) guarantees `.gg/.gg-publish.json` is gitignored before it is first written (appending + committing the `.gitignore` change with a `GgState.updateHash` transplant so recorded check results stay valid). The `doPublish`/`doCommit` GgState keys are still written for `did publish` and the pre-push hook, but the *step* resume no longer relies on content hashes.

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
