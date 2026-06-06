# Changelog

All notable changes to ai-devkit are documented here. release-please appends entries on every merge to `main` based on Conventional Commit messages.


## [1.3.0](https://github.com/amit-t/ai-devkit/compare/v1.2.2...v1.3.0) (2026-06-06)


### Features

* **init:** add Workbench Lite bootstrap with Ralph Devin setup

## [1.2.2](https://github.com/amit-t/ai-devkit/compare/v1.2.1...v1.2.2) (2026-05-14)


### Bug Fixes

* **scan:** aggregate failed on CONTEXT.md without **bold** concepts ([#19](https://github.com/amit-t/ai-devkit/issues/19)) ([03e0e49](https://github.com/amit-t/ai-devkit/commit/03e0e49d2b87431fd9d34b334c5319b7dc716f1d))

## [1.2.1](https://github.com/amit-t/ai-devkit/compare/v1.2.0...v1.2.1) (2026-05-14)


### Bug Fixes

* **install:** two install/upgrade bugs that brick wb.upgrade on macOS ([#17](https://github.com/amit-t/ai-devkit/issues/17)) ([8b6ee77](https://github.com/amit-t/ai-devkit/commit/8b6ee7704d1400bdfe95fb634233f77bbc7a62fb))

## [1.2.0](https://github.com/amit-t/ai-devkit/compare/v1.1.0...v1.2.0) (2026-05-14)


### Features

* WSL2 Ubuntu support (Wave 1) ([02874cd](https://github.com/amit-t/ai-devkit/commit/02874cd5e3621329ff9c1b49be202a75ce387646))

## [1.1.0](https://github.com/amit-t/ai-devkit/compare/v1.0.0...v1.1.0) (2026-05-13)


### Features

* **scan:** add wb-context-scan wrapper library + tests ([99b5b0f](https://github.com/amit-t/ai-devkit/commit/99b5b0fcac5585dcb29876c347cca1bce302508a))
* **scan:** autoscan repo context on init/join + add wb.rescan ([ab03a2a](https://github.com/amit-t/ai-devkit/commit/ab03a2a709eda70cd490e5cbd55265e1fa894a8a))
* **scan:** doctor checks for skill vendoring + context health ([d7c10e7](https://github.com/amit-t/ai-devkit/commit/d7c10e747009f7631aa9a1b1b7dfa59ee091f095))
* **scan:** install symlinks across engines + DEVKIT_DEFAULT_ENGINE env ([1c5aaab](https://github.com/amit-t/ai-devkit/commit/1c5aaab3ecb764a3c09ec3472dc3e30b8343e69b))
* **scan:** vendor repo-context-scan skill + sync script ([e6f4711](https://github.com/amit-t/ai-devkit/commit/e6f4711a17ddeb3dcf0e348c397b92651f0b1fc9))
* **scan:** walk-up wb-root detection in doctor ([c6b7af1](https://github.com/amit-t/ai-devkit/commit/c6b7af1b8ce3b53b273233eae580854d2f1e4ee2))
* **scan:** wire scan step into init.prompt.md + join.prompt.md ([bfa204e](https://github.com/amit-t/ai-devkit/commit/bfa204e69aa3e172c6d2702c7b6c00471d1fb143))


### Bug Fixes

* **scan:** drop flock branch (doesn't survive process boundary); add tiebreaker comment ([e3097ea](https://github.com/amit-t/ai-devkit/commit/e3097ea561106091f5154ece01711fcbf28067e7))
* **scan:** guard `git config user.name` exit code; clean test diagnostics ([9077660](https://github.com/amit-t/ai-devkit/commit/90776605baa513cdb55c4c47c80da776e428dabd))
* **scan:** guard empty HEAD + empty user.name; expand tests ([890ae42](https://github.com/amit-t/ai-devkit/commit/890ae42c4ca93f74bb1db5264c601df2b4e150aa))
* **scan:** normalize upstream_repo to canonical HTTPS + fix usage comment ([d01ce7c](https://github.com/amit-t/ai-devkit/commit/d01ce7c8f0997e4166f9b128eb0f9378feecfff2))
* **test:** stabilize sync-skill + setup-finalize tests on CI ([e63feea](https://github.com/amit-t/ai-devkit/commit/e63feea6c1eadba7cf177b4b41d013146c904730))
* **test:** stabilize sync-skill + setup-finalize tests on CI ([5c8d8aa](https://github.com/amit-t/ai-devkit/commit/5c8d8aab153eaca3dc9b945bbab5e65d939d61aa))

## 1.0.0 (2026-05-09)

* feat: introduce versioning system + `devkit.upgrade` / `wb.upgrade` / `devkit doctor` (initial release).
