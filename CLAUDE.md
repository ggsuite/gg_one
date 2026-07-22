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
- **`did/`** — historical checks (was something done?): `did_commit`, `did_push`, `did_upgrade`
- **`do/`** — actions that execute with validation: `do_commit`, `do_push`, `do_merge`, `do_publish`, `do_configure_publish`, `do_upgrade`, `do_maintain`, `do_checkout`, `create/`
  - `do_checkout <ticket>` fetches and checks out a ticket's branch (delegating to `gg_git`'s `Fetch` + `Checkout`).
  - `do_merge` drops the `.gg/.ticket.json` ticket marker (and its `.gitignore` whitelist) before merging, so it never lands on the main branch.
  - `do_publish` merges through an auto-merge pull request **by default** (`--pr`, GitHub and Azure DevOps): the PR is created with the merge message as title, set to auto-complete with the **squash** strategy (and the message as squash commit message), and the publish waits for the provider merge (`gg_merge`'s `WaitForMerge`, unbounded poll). Afterwards only tags are pushed. `--no-pr` restores the local merge + direct push to main; providers without PR support (e.g. self-hosted GitLab) fall back to the local merge with a warning. Enabling automerge is best-effort: a policy rejection leaves the PR open with a warning and the publish waits for a manual merge.
- **`info/`** — informational queries

### Publish flow (`do_publish` + `do_configure_publish`)

`do publish` resolves all interactive input **up front** — version increment, merge message AND the delete-feature-branch decision (`delete_feature_branch` in the config; `configure-publish` asks it, `--[no-]delete-feature-branch` presets it, and the resolved value is persisted in the runtime file so a resume never re-asks): explicit parameters (the gg_multi flow) / CLI flags > `--config <path>` > an existing `<repo>/.gg/.gg-publish.json` > an automatic interactive `do configure-publish` (which writes that file; `-m` presets the merge message and skips its prompt). No prompt ever sits between the irreversible publish steps. Every default prompt is guarded by `throwWhenNotATerminal` (`tools/terminal_guard.dart`): without a TTY it fails fast with an actionable message instead of hanging (CI, pipes). While the publish runs, per-step progress is recorded in the same `.gg/.gg-publish.json` (`done_steps`: `prepare_version`, `publish_registry`, `merge`, `tag` — the three pushes and the feature-branch deletion are idempotent and always re-run; the deletion tolerates an already-gone remote ref). The file also records the feature `branch`, because a resumed run may find HEAD on the default branch already — but the persisted branch is only trusted **when resuming**; a leftover config-only file (a run that failed in `can publish`) must never pin a stale branch that a later publish would then delete. On full success the file is deleted.

Resume semantics: a leftover file with `done_steps` makes a plain `do publish` **refuse** (resume with `--continue`, discard with `--reconfigure`); `--continue` (or the programmatic `resume: true` that `gg_multi do publish --continue` forwards) skips the done steps and skips `can publish` (the checks would fail on a half-published repo) — but it runs the hash-keyed `did commit` check, which survives gg's own bookkeeping commits and fails exactly when raw commits were added after the failure, so nothing unvalidated is ever published on a resume. When the merge step is already done, the default branch is checked out **before the first push**, so push/tag target the release commit and no push resurrects the possibly already-deleted remote feature branch. `do configure-publish` refuses to overwrite a file that carries `done_steps` (that would silently discard the resume state). `EnsurePublishConfigIgnored` (in `tools/`) guarantees `.gg/.gg-publish.json` is gitignored before it is first written (appending + committing the `.gitignore` change with a `GgState.updateHash` transplant so recorded check results stay valid). Only the `doCommit` GgState key is still written (for the pre-push hook); the former `doPublish`/`doMerge` keys are gone — the *step* resume relies solely on `done_steps` in the git-ignored `.gg/.gg-publish.json`, and `GgState` prunes the legacy keys (`doPrepareVersion`, `doPublishPubDev`, `doMerge`, `doPublishGit`, `doPublish`) from the tracked `.gg/.gg.json` whenever it writes a state. The main-branch push goes through `DoPush.get` (not raw `gitPush`), which records the `doPush` state on the release commit before pushing — otherwise `gg did push` fails on every CI checkout of a freshly published package. The final tag push stays a raw `gitPush(pushTags: true)`, because `DoPush.get` neither pushes tags nor pushes at all once everything is up to date.

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
