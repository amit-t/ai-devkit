# Changelog

All notable changes to ai-devkit are documented here. release-please appends entries on every merge to `main` based on Conventional Commit messages.

## [1.4.0](https://github.com/Invenco-Cloud-Systems-ICS/ai-devkit/compare/v1.3.1...v1.4.0) (2026-06-01)


### Features

* add adopt.auto.wb for adopting existing repos into the workbench template ([29facc6](https://github.com/Invenco-Cloud-Systems-ICS/ai-devkit/commit/29facc67da93733b1b79094895599816a29d2cdd))
* add adopt.auto.wb for adopting existing repos into the workbench template ([eaf62b8](https://github.com/Invenco-Cloud-Systems-ICS/ai-devkit/commit/eaf62b8519a7ae31762429ae0a6c0fc8fe850ee7))
* add init.auto.wb / join.auto.wb / update.auto.wb for test-automation workbench ([61446dc](https://github.com/Invenco-Cloud-Systems-ICS/ai-devkit/commit/61446dc17be6de896373a8147b57ec29db46b37b))
* add init.auto.wb / join.auto.wb / update.auto.wb for test-automation workbench ([99952d7](https://github.com/Invenco-Cloud-Systems-ICS/ai-devkit/commit/99952d768ff0260de0d89438606a361f0bbcb47a))
* **init,join:** wire wb.graphify into init.wb and join.wb prompts ([#26](https://github.com/Invenco-Cloud-Systems-ICS/ai-devkit/issues/26)) ([b90b93a](https://github.com/Invenco-Cloud-Systems-ICS/ai-devkit/commit/b90b93aded2ce2f059a48b2f7baaf64c206a9058))
* **join.auto.wb:** pre-flight repo access check ([4309834](https://github.com/Invenco-Cloud-Systems-ICS/ai-devkit/commit/430983479736cd72d4914f644ece19a2c4b09d58))
* **join.auto.wb:** pre-flight repo access check ([186a61a](https://github.com/Invenco-Cloud-Systems-ICS/ai-devkit/commit/186a61acbb2a1842a1def24681b3f593e90d20ae))
* **orgs:** discover orgs dynamically from `gh api user/orgs` ([fa956d8](https://github.com/Invenco-Cloud-Systems-ICS/ai-devkit/commit/fa956d8fe530d326753c8b4de1910ad77863b1b0))
* **orgs:** discover orgs dynamically from `gh api user/orgs` ([16c3163](https://github.com/Invenco-Cloud-Systems-ICS/ai-devkit/commit/16c31631a9ad4d8d9f55232821e0611be2ad18ff))


### Bug Fixes

* **update.wb:** resolve version nag against wb root, not invocation cwd ([99216db](https://github.com/Invenco-Cloud-Systems-ICS/ai-devkit/commit/99216db0227bfd81b1fb57f1ea5abcacdc492893))
* **update.wb:** resolve version nag against wb root, not invocation cwd ([4d9d4a7](https://github.com/Invenco-Cloud-Systems-ICS/ai-devkit/commit/4d9d4a785c1076a250e5b7cc5235fa36bf192740))

## [1.3.1](https://github.com/amit-t/ai-devkit/compare/v1.3.0...v1.3.1) (2026-05-19)


### Bug Fixes

* **version-check:** recover devkit clone when DEVKIT_CLONE env unset ([#17](https://github.com/amit-t/ai-devkit/issues/17)) ([02bd1bf](https://github.com/amit-t/ai-devkit/commit/02bd1bf885bc022af8cfd9007de256649936f444))

## [1.3.0](https://github.com/amit-t/ai-devkit/compare/v1.2.2...v1.3.0) (2026-05-18)


### Features

* **update,init,join,doctor:** wb.upgrade migrates RALPH_EXECUTION_ENGINE + purges .ralph stub ([293295c](https://github.com/amit-t/ai-devkit/commit/293295c6adc474cd2dfdb6af7914b1a2a12d1102))
* **update,init,join:** wb.upgrade migrates RALPH_EXECUTION_ENGINE + purges .ralph stub ([9db9a66](https://github.com/amit-t/ai-devkit/commit/9db9a66cebaf2bd986fb68d00077a4c6be385beb))

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
