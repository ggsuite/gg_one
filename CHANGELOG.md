# Changelog

## [Unreleased]

### Changed

- feat: language-universal commit/publish via gg\_lang (isDartFamily gating, lockFileFor, registry-aware dispatch)
- test: real PublishConfig tests + dart format tidy; bypass known TOCTOU flake in gg\_state.readSuccess under parallel coverage
- gg\_multi: changed references to git
- gg\_multi: changed references to git
- gg\_multi: changed references to git

## [8.2.1] - 2026-05-19

### Changed

- `CanCommit`: `dart pub get --offline` (or the Flutter equivalent) now runs as
a regular check below the `Can commit?` header and is logged as
`Running "dart pub get --offline"`, matching the style of the other checks
(was framed with `»«` and printed above the header).
- Renamed package from `gg` to `gg_one` and moved the repository to
[https://github.com/ggsuite/gg\_one](https://github.com/ggsuite/gg_one). The previous history (versions
up to and including `7.0.5`) lives at [https://github.com/ggsuite/gg](https://github.com/ggsuite/gg)
at commit `9141ef54f5edac470d119a39285813299143898f`.

## [8.2.0] - 2026-05-19

### Changed

- gg\_multi: changed references to git

## [8.1.1] - 2026-05-19

### Changed

- gg\_multi: changed references to git
- Gg Multi: changed references to pub.dev

## [8.1.0] - 2026-05-12

### Changed

- gg\_multi: changed references to git

## [7.0.5] - 2026-05-04

## [7.0.4] - 2026-04-28

### Changed

- Execute git fetch and git pull on the main branch before merging in gg do merge

## [7.0.3] - 2026-04-23

### Changed

- Refactor: resolve delete-feature-branch only when needed
- Create ticket for lazy-resolve-delete-feature-branch

## [7.0.2] - 2026-04-23

## [7.0.1] - 2026-04-22

## [7.0.0] - 2026-04-20

## [6.3.1] - 2026-04-15

## [6.3.0] - 2026-04-13

## [6.2.0] - 2026-04-13

### Changed

- kidney: changed references to local

## [6.1.4] - 2026-04-10

## [6.1.3] - 2026-04-07

### Changed

- Kidney: changed references to pub.dev

## [6.1.2] - 2026-03-30

## [6.1.1] - 2026-03-29

### Fixed

- Bugfix http client

## [6.1.0] - 2026-03-29

### Added

- Add message to do publish

## [6.0.5] - 2026-03-27

### Fixed

- bugfix-closed-client

## [6.0.4] - 2026-03-27

### Changed

- new gg version

## [6.0.3] - 2026-03-27

# <<<<<<< Updated upstream

### Changed

- kidney: changed references to git

### Fixed

- bugfix tagging in gg do publish

## [6.0.2] - 2026-03-27

> > > > > > > Stashed changes

### Changed

- kidney: changed references to path

## [6.0.1] - 2026-03-26

### Added

- Add: push after publish

## [6.0.0] - 2026-03-26

### Changed

- Refactor do\_publish to use gitPush with pushTags and update tests
- Wrap checkout logic in status printer for progress output

## [5.1.0] - 2026-03-19

### Fixed

- Fix mock param in do\_checkout\_test and update checkout error check

## [5.0.1] - 2026-03-16

### Changed

- Change commit message to 'Finish development of version X'

## [5.0.0] - 2026-03-16

### Added

- Add do\_checkout command to support branch checkout with stash

### Changed

- Apply git stash if checkout fails and rethrow the error

### Removed

- Remove IsVersionPrepared check from CanPublish command flow

## [4.0.7] - 2026-03-08

### Added

- Add VersionSelector with interact support and related tests
- Add IsFeatureBranch to CanPublish and update dependencies

### Changed

- move .gg.json to .gg/.gg.json and update related code/tests
- Refactor do\_publish to add version selector and local merge step

### Fixed

- Fix copy right header in auto created Test files

## [4.0.6] - 2026-01-20

### Changed

- Remove pubspec.yaml from change detection ignore files

## [4.0.5] - 2026-01-20

### Changed

- Ignore missing version in CHANGELOG when running pana because version is managed by gg

## [4.0.4] - 2025-08-16

### Added

- Add --ignoreUnstaged option to gg can commit and gg can push
- Update gg\_merge to version 1.0.2
- BREAKING CHANGE: V.5.0.0: Git must be set to EOF LF
- Add message parameter to exec and get in do merge

## [4.0.3] - 2025-08-16

### Changed

- Allow to print details using -v option on gg info last-changes-hash

## [4.0.2] - 2025-08-11

### Added

- Add .gitattributes file
- Add pubspeck.lock and .kidney\_status to ignored files

## [4.0.1] - 2025-08-11

## [4.0.0] - 2025-08-11

## [3.1.1] - 2025-08-11

## [3.1.0] - 2025-08-02

### Added

- add tests for merge
- Add message parameter to gg merge

### Changed

- Prepare version 3.1.0

## [3.0.25] - 2025-07-31

### Changed

- Update gg\_test to version 1.1.7

## [3.0.24] - 2025-07-09

### Changed

- Update version of gg\_test

### Removed

- remove publish\_to: none

## [3.0.23] - 2025-06-19

### Added

- Add options to prevent tagging and version-increase after publishing

### Changed

- Do not add version tag automatically. Use --add-version-tag to add the tag.

## [3.0.22] - 2025-06-09

### Changed

- Improve error message on version errors.

## [3.0.21] - 2025-06-07

### Changed

- Improve hashing algorithm

## [3.0.20] - 2025-06-07

### Fixed

- Fix a missing error output on test errors

## [3.0.19] - 2025-06-07

### Changed

- Print more details when tests fail

## [3.0.18] - 2025-06-05

### Changed

- Improve error message
- Update to dart 3.8.0
- Don't add log type to commit message
- Some change
- When not existing gg do push creates an upstream branch on the remote

### Fixed

- Require -m prefix for gg do commit

## [3.0.17] - 2025-02-28

### Changed

- Upgrade to dart 3.7

## [3.0.16] - 2024-11-27

### Changed

- Replace gg\_json by gg\_direct\_json

## [3.0.15] - 2024-10-03

### Changed

- When commit with ammendWhenNotPushed = true is called and no upstream branch is set, changes will be ammended

### Fixed

- Fix pana issues

## [3.0.14] - 2024-09-04

### Changed

- Exclude l10 from coverage

## [3.0.13] - 2024-09-04

### Changed

- Don't expect tests for l10n folders

## [3.0.12] - 2024-08-30

### Changed

- Change launch.json
- Test change
- Prevent updating the hash for CanUpgrade.

## [3.0.11] - 2024-08-30

### Changed

- Pretty print .gg.json
- Hashes wil be calculated independent of line feeds

## [3.0.10] - 2024-08-30

### Changed

- Update dependencies to latest versions
- Make pana work on windows
- Run tests on MacOS

## [3.0.9] - 2024-08-24

### Changed

- Show detailed test errors when running on a github pipeline

## [3.0.8] - 2024-08-24

### Changed

- Update gg\_test to 1.0.19. Only failing error lines are shown, but not details.

## [3.0.7] - 2024-08-20

### Fixed

- Fix an issue with binary file hash calculation

## [3.0.6] - 2024-06-21

### Changed

- Update to new version of gg\_tests

## [3.0.5] - 2024-06-21

### Fixed

- Fix issue with generated files

## [3.0.4] - 2024-04-13

### Removed

- Removed neccessity to specify a log type when running »gg do commit«

## [3.0.3] - 2024-04-13

### Added

- missing ✅ for message Tag 1.2.3 added

## [3.0.2] - 2024-04-13

### Changed

- Use a globally installed pana to make pana check

### Removed

- dependency pana

## [3.0.1] - 2024-04-13

### Added

- mocks for DidPush, DidPublish
- DidUpgrade
- CanUpgrade, Improve mocks
- upgrade dependencies and make tests work again
- Tests for DoUpgrade
- did upgrade only checks if changes are available on pub.dev
- DoMaintain to check if everything is upgraded and published from time to time

### Changed

- Parentheses are not necessary anymore
- improved comments of DidCommit, DidPublish and DidPush
- Improved help for CanCommit, CanPush, CanPublish
- DidUpgrade checks also if everything is upgraded

### Removed

- Upgrade check before pushing
- dependency to gg\_install\_gg, remove ./check script
- Upgrading does not trigger a commit and a publish

## [3.0.0] - 2024-04-10

### Changed

- BREAKING CHANGE: Interface of »gg do commit« has changed.

## [2.0.5] - 2024-04-10

### Fixed

- DoPublish: Don't confirm package not published to pub.dev, small fixes
- Pipeline: Disable cache

## [2.0.4] - 2024-04-09

### Changed

- Don't check pana on packages not published to pub.dev

### Fixed

- Various fixes to make non-pub.dev repos work

## [2.0.3] - 2024-04-09

### Added

- Handle unpublished packages as well packages that are not published to pub.dev

### Changed

- Update latest changes on gg\_publish and gg\_git
- Refactor tests

## [2.0.2] - 2024-04-06

### Fixed

- Changes were not correctly submitted on publish

## [2.0.1] - 2024-04-06

### Changed

- Pipeline: Improve order and description of tasks
- Commit message of .gg.json commit

### Fixed

- doPush did not push success state result when state was pushed before

## [2.0.0] - 2024-04-06

### Added

- New sub command »gg info modified-files and »gg info »last-changes-hash«
- DoCommit: When everything is committed, no message an log type are needed.
- Option --no-log to allow committing without change CHANGELOG.md
- Pipeline: Print modified files + changes hash

### Changed

- Pipeline: Use globally installed version of gg
- Kidney: Auto check all repos
- Breaking change: Renamed log type values into add \| change \| deprecate \| fix \| remove \| secure

### Fixed

- Wrong option in command line output
- An error which can lead to sporadic test fails

## [1.0.16] - 2024-04-05

### Added

- Code to fix pipeline issues
- --force flag to tests on pipeline
- Renamed -l flag into -t for gg do commit

### Changed

- Cleaned up pipeline
- Prepare publishing

## [1.0.15] - 2024-04-05

### Added

- --save-state option for commands like gg can commit\n\nThis is needed to make GitHub pipelines work
- Setup pipeline git username and email
- pubspec.lock to .gitignore
- Add various outputs to test pipeline issues

### Removed

- Removed unused sample project
- logStatus is replaced by GgStatusPrinter
- isGitHub is replaced by gg\_is\_github
- Pipeline: remove --no-save-state flag

## [1.0.14] - 2024-04-05

### Added

- gg do commit/publish edits CHANGELOG.md

### Fixed

- Broken links in CHANGELOG.md, wrong commit messages
- Remove unneccessary commandline output

## [1.0.12] - 2024-04-04

- Initial version

# <<<<<<< Updated upstream

[Unreleased](https://github.com/inlavigo/gg/compare/6.0.2...HEAD): https://github.com/inlavigo/gg/compare/6.0.1...HEAD

> > > > > > > Stashed changes

[Unreleased]: https://github.com/ggsuite/gg_one/compare/8.2.1...HEAD
[8.2.1]: https://github.com/ggsuite/gg_one/compare/8.2.0...8.2.1
[8.2.0]: https://github.com/ggsuite/gg_one/compare/8.1.1...8.2.0
[8.1.1]: https://github.com/ggsuite/gg_one/compare/8.1.0...8.1.1
[8.1.0]: https://github.com/ggsuite/gg_one/compare/7.0.5...8.1.0
[7.0.5]: https://github.com/inlavigo/gg/compare/7.0.4...7.0.5
[7.0.4]: https://github.com/inlavigo/gg/compare/7.0.3...7.0.4
[7.0.3]: https://github.com/inlavigo/gg/compare/7.0.2...7.0.3
[7.0.2]: https://github.com/inlavigo/gg/compare/7.0.1...7.0.2
[7.0.1]: https://github.com/inlavigo/gg/compare/7.0.0...7.0.1
[7.0.0]: https://github.com/inlavigo/gg/compare/6.3.1...7.0.0
[6.3.1]: https://github.com/inlavigo/gg/compare/6.3.0...6.3.1
[6.3.0]: https://github.com/inlavigo/gg/compare/6.2.0...6.3.0
[6.2.0]: https://github.com/inlavigo/gg/compare/6.1.4...6.2.0
[6.1.4]: https://github.com/inlavigo/gg/compare/6.1.3...6.1.4
[6.1.3]: https://github.com/inlavigo/gg/compare/6.1.2...6.1.3
[6.1.2]: https://github.com/inlavigo/gg/compare/6.1.1...6.1.2
[6.1.1]: https://github.com/inlavigo/gg/compare/6.1.0...6.1.1
[6.1.0]: https://github.com/inlavigo/gg/compare/6.0.5...6.1.0
[6.0.5]: https://github.com/inlavigo/gg/compare/6.0.4...6.0.5
[6.0.4]: https://github.com/inlavigo/gg/compare/6.0.3...6.0.4
[6.0.3]: https://github.com/inlavigo/gg/compare/6.0.2...6.0.3
[6.0.2]: https://github.com/inlavigo/gg/compare/6.0.1...6.0.2
[6.0.1]: https://github.com/inlavigo/gg/compare/6.0.0...6.0.1
[6.0.0]: https://github.com/inlavigo/gg/compare/5.1.0...6.0.0
[5.1.0]: https://github.com/inlavigo/gg/compare/5.0.1...5.1.0
[5.0.1]: https://github.com/inlavigo/gg/compare/5.0.0...5.0.1
[5.0.0]: https://github.com/inlavigo/gg/compare/4.0.7...5.0.0
[4.0.7]: https://github.com/inlavigo/gg/compare/4.0.6...4.0.7
[4.0.6]: https://github.com/inlavigo/gg/compare/4.0.5...4.0.6
[4.0.5]: https://github.com/inlavigo/gg/compare/4.0.4...4.0.5
[4.0.4]: https://github.com/inlavigo/gg/compare/4.0.3...4.0.4
[4.0.3]: https://github.com/inlavigo/gg/compare/4.0.2...4.0.3
[4.0.2]: https://github.com/inlavigo/gg/compare/4.0.1...4.0.2
[4.0.1]: https://github.com/inlavigo/gg/compare/4.0.0...4.0.1
[4.0.0]: https://github.com/inlavigo/gg/compare/3.1.1...4.0.0
[3.1.1]: https://github.com/inlavigo/gg/compare/3.1.0...3.1.1
[3.1.0]: https://github.com/inlavigo/gg/compare/3.0.25...3.1.0
[3.0.25]: https://github.com/inlavigo/gg/compare/3.0.24...3.0.25
[3.0.24]: https://github.com/inlavigo/gg/compare/3.0.23...3.0.24
[3.0.23]: https://github.com/inlavigo/gg/compare/3.0.22...3.0.23
[3.0.22]: https://github.com/inlavigo/gg/compare/3.0.21...3.0.22
[3.0.21]: https://github.com/inlavigo/gg/compare/3.0.20...3.0.21
[3.0.20]: https://github.com/inlavigo/gg/compare/3.0.19...3.0.20
[3.0.19]: https://github.com/inlavigo/gg/compare/3.0.18...3.0.19
[3.0.18]: https://github.com/inlavigo/gg/compare/3.0.17...3.0.18
[3.0.17]: https://github.com/inlavigo/gg/compare/3.0.16...3.0.17
[3.0.16]: https://github.com/inlavigo/gg/compare/3.0.15...3.0.16
[3.0.15]: https://github.com/inlavigo/gg/compare/3.0.14...3.0.15
[3.0.14]: https://github.com/inlavigo/gg/compare/3.0.13...3.0.14
[3.0.13]: https://github.com/inlavigo/gg/compare/3.0.12...3.0.13
[3.0.12]: https://github.com/inlavigo/gg/compare/3.0.11...3.0.12
[3.0.11]: https://github.com/inlavigo/gg/compare/3.0.10...3.0.11
[3.0.10]: https://github.com/inlavigo/gg/compare/3.0.9...3.0.10
[3.0.9]: https://github.com/inlavigo/gg/compare/3.0.8...3.0.9
[3.0.8]: https://github.com/inlavigo/gg/compare/3.0.7...3.0.8
[3.0.7]: https://github.com/inlavigo/gg/compare/3.0.6...3.0.7
[3.0.6]: https://github.com/inlavigo/gg/compare/3.0.5...3.0.6
[3.0.5]: https://github.com/inlavigo/gg/compare/3.0.4...3.0.5
[3.0.4]: https://github.com/inlavigo/gg/compare/3.0.3...3.0.4
[3.0.3]: https://github.com/inlavigo/gg/compare/3.0.2...3.0.3
[3.0.2]: https://github.com/inlavigo/gg/compare/3.0.1...3.0.2
[3.0.1]: https://github.com/inlavigo/gg/compare/3.0.0...3.0.1
[3.0.0]: https://github.com/inlavigo/gg/compare/2.0.5...3.0.0
[2.0.5]: https://github.com/inlavigo/gg/compare/2.0.4...2.0.5
[2.0.4]: https://github.com/inlavigo/gg/compare/2.0.3...2.0.4
[2.0.3]: https://github.com/inlavigo/gg/compare/2.0.2...2.0.3
[2.0.2]: https://github.com/inlavigo/gg/compare/2.0.1...2.0.2
[2.0.1]: https://github.com/inlavigo/gg/compare/2.0.0...2.0.1
[2.0.0]: https://github.com/inlavigo/gg/compare/1.0.16...2.0.0
[1.0.16]: https://github.com/inlavigo/gg/compare/1.0.15...1.0.16
[1.0.15]: https://github.com/inlavigo/gg/compare/1.0.14...1.0.15
[1.0.14]: https://github.com/inlavigo/gg/compare/1.0.12...1.0.14
[1.0.12]: https://github.com/inlavigo/gg/releases/tag/1.0.12
