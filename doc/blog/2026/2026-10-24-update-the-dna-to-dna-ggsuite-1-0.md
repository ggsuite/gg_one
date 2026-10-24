<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Update the DNA to dna_ggsuite 1.0

## Motivation

- gg_one bundles `gg_one_core`, `gg_one_commit`, `gg_one_merge` and
  `gg_one_do_publish` into one command line and re-exports them
- Its own change is small: its guides, skills and the managed block of
  `CLAUDE.md`, generated from the dna_ggsuite DNA, are brought to 1.0
- The bundled packages change more; their changes reach the command line
  of gg_one, so this post lists them under "Dependency updates"

## Strategy

- Raise the dev dependency `dna_ggsuite` from ^0.5.0 to ^1.0.0
- Let helix regenerate the DNA files, committed as `#gg: generated DNA`
- Change nothing in `lib/`, `bin/` and `test/`; the bundled packages come
  in through the existing caret constraints

## Implementation 1: Ticket workflow

- New skill `/gg-review`: checks the diff of every repo against its scope,
  writes the blog posts, updates README.md and `index.jsonc`, then opens
  the pull requests and runs `/review-light`
- The blog posts move from the publish to the review phase; `/gg` and the
  `CLAUDE.md` block list `/gg-review`, `/gg-publish` checks for the post
- `/gg-commit` proposes one message per repo, in the repo's own terms;
  repos that depend on each other are committed one by one
- `ai-dev-guide.md` and `/gg-ticket` gain: keep every repo in its scope,
  keep the `index.jsonc` up to date, describe every repo in its own terms,
  and engineer the requirements before the plan

## Implementation 2: Code guides and prompts

- The code guide no longer asks for the package prefix on types and file
  names; the examples of code and test guide read `User`, not `GgUser`
- New hooks in `.claude/settings.json` keep the prompts, never the
  answers, in the project management repo, with tokens redacted

## Dependency updates

- `dna_ggsuite` 1.0.0 brings `dna_gg` 1.0.0 (workflow skills, AI guide,
  hooks) and `dna_clean_code` 0.2.2 (code and test guides)
- `gg_one_commit`: `do upgrade deps` runs `dart pub upgrade` without
  `--tighten` by default; the new flag `--tighten` opts in. With local
  overrides, pub may raise a lower bound past the upper one and crash
- `gg_one_commit`: `DoCommit.needsMessage` tells whether a repo needs a
  commit message: for uncommitted changes, or for unrecorded commits that
  need a CHANGELOG entry
- `gg_one_do_publish`: `do publish` passes `tighten: true`, so a release
  still tightens its constraints, after the overrides are gone
- `gg_one_core`: when pana prints no JSON report, the error names pana's
  exit code and its SEVERE and SHOUT log records, or the last ten lines of
  stderr; pana 0.23.17 and later fail so on a Windows temp folder
- `gg_one_core`: in a `#gg: generated DNA` commit, the files listed in
  `dna/_generated.json`, the list itself and `CLAUDE.md` count as bookkeeping;
  a DNA update alone needs no commit message and no CHANGELOG entry
- `gg_one_merge` only upgraded its DNA
- `gg_process` starts commands the PATH holds only as `.bat` or `.cmd`,
  like `flutter`, through the shell on Windows
- `gg_test`, run by the checks of `gg_one_core`, demands no coverage for
  files whose test excludes the platform with a file-level `@TestOn`

## Open Points

- The lower bounds on the bundled packages still name their previous
  versions; the publish tightens them to the new releases
- `.claude/hooks/pm-prompts.json` names no project management repo yet, so
  the hooks keep no prompts; they need Node.js to run at all
- The repo has no `index.jsonc` yet, although the new guides ask for one
- `pubspec_overrides.yaml` points the dependencies at the sibling
  checkouts while the ticket is open; it goes when the references return
  to pub.dev
