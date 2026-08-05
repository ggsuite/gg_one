# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

`gg_one` is the umbrella CLI of the gg_one tool family: pre-commit checks and git workflow automation (commit, push, merge, publish) for dart, flutter and TypeScript repos. Since v13 the implementation lives in four sub-packages; this repo only wires them into one command line and re-exports their APIs for consumers like gg_multi.

## The package family

| Package | Contents |
|---|---|
| `gg_one_core` | The foundation, three concerns in one package: the **state kernel** (`GgState` with `.gg/gg.json` hash caching, `CommandCluster`, `DidCommand`, `Suggestion`, pubspec-overrides backup), the **checks** (`Analyze`, `Format`, `Build`, `Pana`, `NpmLoggedIn`, `NoPubspecOverrides`, `CheckPackageJsonScripts`, `PubGetOffline` plus `Analyzer`, `Formatter` and the `Checks` container) and the **publish configuration** (`PublishConfig`, `VersionSelector`, terminal guard, `EnsurePublishConfigIgnored`, `DoConfigurePublish`) |
| `gg_one_commit` | Daily flows: `CanCommit`/`DoCommit`/`DidCommit`, `CanPush`/`DoPush`/`DidPush`, upgrade flow (`DoUpgradeDeps`), ticket flow (`CreateTicket`, `CanCheckout`), ocean folder guard, repository url |
| `gg_one_merge` | `MergeFlow`, `CreatePullRequest`, lock-file helpers, `CanMerge` |
| `gg_one_do_publish` | `DoPublish` (the publish orchestrator), `CanPublish`, `DidPublish`, workspace folder guard, version tag tools |

Dependency direction (acyclic): `do_publish` → `merge` → `commit` → `core`. Inside `gg_one_core` the checks layer stays independent of the state kernel — no `GgState`, no `CommandCluster` — which is what keeps that boundary re-splittable. This repo depends on all four and keeps `lib/gg_one.dart` as a pure re-export barrel, so `package:gg_one/gg_one.dart` still exposes the whole family (plus the `gg_lang` project-type re-exports).

What stays here: `Gg` (root command), the group commands `Can`/`Did`/`Do`/`Info` with their `DepsOf*` DI containers, `Create`/`DoUpgrade`/`DidUpgrade` group registration, `bin/gg_one.dart`.

In a ticket workspace the sub-packages are wired via `pubspec_overrides.yaml` path overrides; `gg do publish` publishes them in dependency order and removes the overrides.

## Commands

```bash
dart test                # this repo's own (fast) suite
dart analyze
dart format .
```

Detailed behavior documentation (publish flow, resume semantics, guards, merge-only mode) lives in the sub-package repos next to the code it describes.

## Testing Conventions

- 100% code coverage is required. Exempt lines with `// coverage:ignore-line` or `// coverage:ignore-start` / `// coverage:ignore-end`.
- Each implementation file must have a corresponding `_test.dart` in the mirrored path under `test/`.
- Mock classes are defined at the bottom of the **same file** as the class they mock, using `mocktail` and extending `MockDirCommand<T>` — in every package of the family.
- Tests use `gg_git_test_helpers` (including the cached repo helpers) and `gg_capture_print`.
