# Changelog

All notable changes to ai-devkit are documented here. release-please appends entries on every merge to `main` based on Conventional Commit messages.


## [1.6.0](https://github.com/amit-t/ai-devkit/compare/v1.5.0...v1.6.0) (2026-06-06)


### Features

* add init.auto.wb / join.auto.wb / update.auto.wb for test-automation workbench ([61446dc](https://github.com/amit-t/ai-devkit/commit/61446dc17be6de896373a8147b57ec29db46b37b))
* add init.auto.wb / join.auto.wb / update.auto.wb for test-automation workbench ([99952d7](https://github.com/amit-t/ai-devkit/commit/99952d768ff0260de0d89438606a361f0bbcb47a))
* bootstrap ralph workspace in init.wb / join.wb / update.wb (Plan F) ([ef184e7](https://github.com/amit-t/ai-devkit/commit/ef184e7c261bbd9fd9ebe9dce3448b544cdca1e3))
* bootstrap ralph workspace in init.wb / join.wb / update.wb (Plan F) ([901aee1](https://github.com/amit-t/ai-devkit/commit/901aee1eb4f948b21d114c0571e600d3b2bd3a6a))
* bootstrap ralph workspace mode during init.wb / join.wb ([480d286](https://github.com/amit-t/ai-devkit/commit/480d286b87cc6bba312b40e6b4756ea07cb56c47))
* **devkit:** add devkit doctor with --check-only / --fix ([3202035](https://github.com/amit-t/ai-devkit/commit/3202035f318421ee787c2e1530ed681ca8eb8591))
* **devkit:** add devkit.upgrade with --yes / --rollback / --force / dirty-refusal ([f822635](https://github.com/amit-t/ai-devkit/commit/f822635fc390038c60f47f180f04970cec73a934))
* **devkit:** tag stamped wbs with ai-workbench topic; print steering drift on update.wb ([180d8bf](https://github.com/amit-t/ai-devkit/commit/180d8bf5f4c2e993c70ac42c01aa36f459164143))
* **devkit:** tag stamped wbs with ai-workbench topic; print steering drift on update.wb ([0e0b89e](https://github.com/amit-t/ai-devkit/commit/0e0b89e55f9a68caa4666724ebcfe59e2b8f07a3))
* **devkit:** tag stamped wbs with ai-workbench topic; print steering drift on update.wb ([f1db0e4](https://github.com/amit-t/ai-devkit/commit/f1db0e40597d4357adbd458e70c0b207e2a0d591))
* **init,join:** wire wb.graphify into init.wb and join.wb prompts ([#27](https://github.com/amit-t/ai-devkit/issues/27)) ([f7d1761](https://github.com/amit-t/ai-devkit/commit/f7d1761747b6eb045dec69f409ac85fe586e600a))
* **init.wb:** mint workbench- prefix, keep wb- backward compatible ([#28](https://github.com/amit-t/ai-devkit/issues/28)) ([0725ba2](https://github.com/amit-t/ai-devkit/commit/0725ba29009778f839c9c96562a892f5d7ad6d8e))
* **init:** add Workbench Lite bootstrap ([#36](https://github.com/amit-t/ai-devkit/issues/36)) ([82756b8](https://github.com/amit-t/ai-devkit/commit/82756b897da1610c5e193b250b6c7f2aa2cf4725))
* initial devkit CLI ([549d970](https://github.com/amit-t/ai-devkit/commit/549d970ca7caa08f3a769e57762b933d25606ca4))
* **init:** stamp template-version.json at workbench creation ([13b6021](https://github.com/amit-t/ai-devkit/commit/13b60219cc9e0c210df99d2d7d0c853b206e9744))
* **install:** drop versioning lib, write DEVKIT_CLONE, install upgrade/doctor commands, deprecate update.wb ([fee85f1](https://github.com/amit-t/ai-devkit/commit/fee85f1750698c3e35e223cbacde1b9dd12a1961))
* **join.auto.wb:** pre-flight repo access check ([4309834](https://github.com/amit-t/ai-devkit/commit/430983479736cd72d4914f644ece19a2c4b09d58))
* **join.auto.wb:** pre-flight repo access check ([186a61a](https://github.com/amit-t/ai-devkit/commit/186a61acbb2a1842a1def24681b3f593e90d20ae))
* **orgs:** discover orgs dynamically from `gh api user/orgs` ([fa956d8](https://github.com/amit-t/ai-devkit/commit/fa956d8fe530d326753c8b4de1910ad77863b1b0))
* **orgs:** discover orgs dynamically from `gh api user/orgs` ([16c3163](https://github.com/amit-t/ai-devkit/commit/16c31631a9ad4d8d9f55232821e0611be2ad18ff))
* preflight checks, ai-ralph bootstrap, orgs utility ([4a2040a](https://github.com/amit-t/ai-devkit/commit/4a2040a5bc875742ce8fc0d6317b7ab89bf500b7))
* **scan:** add wb-context-scan wrapper library + tests ([99b5b0f](https://github.com/amit-t/ai-devkit/commit/99b5b0fcac5585dcb29876c347cca1bce302508a))
* **scan:** autoscan repo context on init/join + add wb.rescan ([ab03a2a](https://github.com/amit-t/ai-devkit/commit/ab03a2a709eda70cd490e5cbd55265e1fa894a8a))
* **scan:** doctor checks for skill vendoring + context health ([d7c10e7](https://github.com/amit-t/ai-devkit/commit/d7c10e747009f7631aa9a1b1b7dfa59ee091f095))
* **scan:** install symlinks across engines + DEVKIT_DEFAULT_ENGINE env ([1c5aaab](https://github.com/amit-t/ai-devkit/commit/1c5aaab3ecb764a3c09ec3472dc3e30b8343e69b))
* **scan:** vendor repo-context-scan skill + sync script ([e6f4711](https://github.com/amit-t/ai-devkit/commit/e6f4711a17ddeb3dcf0e348c397b92651f0b1fc9))
* **scan:** walk-up wb-root detection in doctor ([c6b7af1](https://github.com/amit-t/ai-devkit/commit/c6b7af1b8ce3b53b273233eae580854d2f1e4ee2))
* **scan:** wire scan step into init.prompt.md + join.prompt.md ([bfa204e](https://github.com/amit-t/ai-devkit/commit/bfa204e69aa3e172c6d2702c7b6c00471d1fb143))
* **update,init,join,doctor:** wb.upgrade migrates RALPH_EXECUTION_ENGINE + purges .ralph stub ([293295c](https://github.com/amit-t/ai-devkit/commit/293295c6adc474cd2dfdb6af7914b1a2a12d1102))
* **update,init,join:** wb.upgrade migrates RALPH_EXECUTION_ENGINE + purges .ralph stub ([9db9a66](https://github.com/amit-t/ai-devkit/commit/9db9a66cebaf2bd986fb68d00077a4c6be385beb))
* **update.wb:** migrate old stamped wbs to ralph workspace mode ([420cb6b](https://github.com/amit-t/ai-devkit/commit/420cb6b963ea339392f90b4349d879834b6a4042))
* versioning foundation (devkit + lib + doctor + wb.upgrade rename) ([8836a31](https://github.com/amit-t/ai-devkit/commit/8836a3188dc6c6d6cdd43d98562097b337345bc1))
* versioning foundation (devkit + lib + doctor + wb.upgrade rename) ([63de75c](https://github.com/amit-t/ai-devkit/commit/63de75cf9d1bfeb747ce20a094ed3de4db9857dd))
* versioning foundation (devkit + lib + doctor + wb.upgrade rename) ([e0a5b73](https://github.com/amit-t/ai-devkit/commit/e0a5b733c57a1680c5f9cdf6bf7cfe3481c880ff))
* **versioning:** add _wb_check_requires constraint parser ([3b720ef](https://github.com/amit-t/ai-devkit/commit/3b720efc5ed2b8aa1ced482b104480cc074a1a01))
* **versioning:** add _wb_clone_path helper ([ded63fb](https://github.com/amit-t/ai-devkit/commit/ded63fb4528022aeb597dc1a46ef994722d9703c))
* **versioning:** add _wb_compare_semver in lib/version-check.sh ([ac7d1f5](https://github.com/amit-t/ai-devkit/commit/ac7d1f5a4374caa5045725ae0563a20d2ec6723b))
* **versioning:** add _wb_fetch_upstream with gh + git fallback ([5055825](https://github.com/amit-t/ai-devkit/commit/5055825aab67867516d0320e86bbad87ebce335f))
* **versioning:** add _wb_local_version reader ([1e2e57d](https://github.com/amit-t/ai-devkit/commit/1e2e57d429eae0ef693710c97561911b340ce521))
* **versioning:** add _wb_record_prior for rollback support ([612860f](https://github.com/amit-t/ai-devkit/commit/612860f531fcf48dc748935c8bee9ba201bd2800))
* **versioning:** add _wb_render_banner ([49b20c7](https://github.com/amit-t/ai-devkit/commit/49b20c735b23083bade18fa364c656cb69bf79a9))
* **versioning:** add one-time bootstrap nag ([10943d6](https://github.com/amit-t/ai-devkit/commit/10943d689110ae402ff9522c9e01d10515109879))
* **versioning:** add TTL-aware cache layer ([173ef0c](https://github.com/amit-t/ai-devkit/commit/173ef0c691f1aa29b321b6e06f1e947ab5e27c47))
* **versioning:** orchestrate fetch+cache+banner via _wb_versioncheck ([7adc612](https://github.com/amit-t/ai-devkit/commit/7adc6120924c64d5dfb1fc28709a017865029f9e))
* **versioning:** wire _wb_versioncheck preamble into init/join/update entry scripts ([f999d49](https://github.com/amit-t/ai-devkit/commit/f999d492ed1e79371bb16e36e1d5f8cbe251687e))
* **version:** seed version.json at 1.0.0 and CHANGELOG ([09209bc](https://github.com/amit-t/ai-devkit/commit/09209bc56a315fa9692ffe74c721f2293caaf421))
* **wb-upgrade:** stamp .workbench-state/template-version.json after merge ([19599d7](https://github.com/amit-t/ai-devkit/commit/19599d7c6cfdb702ddea5862d92b9310dbe7dfbb))
* WSL2 Ubuntu support (Wave 1) ([02874cd](https://github.com/amit-t/ai-devkit/commit/02874cd5e3621329ff9c1b49be202a75ce387646))


### Bug Fixes

* **install:** strip stale DEVKIT_CLONE before appending to ~/.zprofile ([e3a6e57](https://github.com/amit-t/ai-devkit/commit/e3a6e57564a1a329406221270789e87c04b5adea))
* **install:** two install/upgrade bugs that brick wb.upgrade on macOS ([#17](https://github.com/amit-t/ai-devkit/issues/17)) ([8b6ee77](https://github.com/amit-t/ai-devkit/commit/8b6ee7704d1400bdfe95fb634233f77bbc7a62fb))
* **orgs.wb,init.wb:** resolve symlink + rebuild stale template .ralph ([72518c5](https://github.com/amit-t/ai-devkit/commit/72518c588200195eb0258eac52602aa198d7966f))
* **orgs.wb,init.wb:** resolve symlink + rebuild stale template .ralph ([6413d5e](https://github.com/amit-t/ai-devkit/commit/6413d5e56a4a0144356ef4a7e05406dd71c3a6ea))
* **orgs.wb,init.wb:** resolve symlink + rebuild stale template .ralph ([424f6c3](https://github.com/amit-t/ai-devkit/commit/424f6c313dc67d462bda43a2df4f13af67c04622))
* **orgs.wb,init.wb:** resolve symlink + rebuild stale template .ralph ([6a213e6](https://github.com/amit-t/ai-devkit/commit/6a213e68f972ebdca4b12ccde34ea34d419d23ee))
* **scan:** aggregate failed on CONTEXT.md without **bold** concepts ([#19](https://github.com/amit-t/ai-devkit/issues/19)) ([03e0e49](https://github.com/amit-t/ai-devkit/commit/03e0e49d2b87431fd9d34b334c5319b7dc716f1d))
* **scan:** drop flock branch (doesn't survive process boundary); add tiebreaker comment ([e3097ea](https://github.com/amit-t/ai-devkit/commit/e3097ea561106091f5154ece01711fcbf28067e7))
* **scan:** guard `git config user.name` exit code; clean test diagnostics ([9077660](https://github.com/amit-t/ai-devkit/commit/90776605baa513cdb55c4c47c80da776e428dabd))
* **scan:** guard empty HEAD + empty user.name; expand tests ([890ae42](https://github.com/amit-t/ai-devkit/commit/890ae42c4ca93f74bb1db5264c601df2b4e150aa))
* **scan:** normalize upstream_repo to canonical HTTPS + fix usage comment ([d01ce7c](https://github.com/amit-t/ai-devkit/commit/d01ce7c8f0997e4166f9b128eb0f9378feecfff2))
* **test:** pin bare-upstream HEAD to refs/heads/main ([4806db6](https://github.com/amit-t/ai-devkit/commit/4806db6772dfb11ec8e23164f32b90f90f077abf))
* **test:** stabilize sync-skill + setup-finalize tests on CI ([e63feea](https://github.com/amit-t/ai-devkit/commit/e63feea6c1eadba7cf177b4b41d013146c904730))
* **test:** stabilize sync-skill + setup-finalize tests on CI ([5c8d8aa](https://github.com/amit-t/ai-devkit/commit/5c8d8aab153eaca3dc9b945bbab5e65d939d61aa))
* **update.wb:** resolve version nag against wb root, not invocation cwd ([#26](https://github.com/amit-t/ai-devkit/issues/26)) ([732d05b](https://github.com/amit-t/ai-devkit/commit/732d05b66342b2af6eb9948ed8a95898c7648823))
* **version-check,install:** recover clone path when DEVKIT_CLONE env unset ([51298ed](https://github.com/amit-t/ai-devkit/commit/51298ed0c21be3f0c2b546ca8c87e6fbb725962e))
* **version-check,install:** recover clone path when DEVKIT_CLONE env unset ([ba8ded0](https://github.com/amit-t/ai-devkit/commit/ba8ded0490111d4774d3bed632755d92016b93b9))
* **version-check:** recover devkit clone when DEVKIT_CLONE env unset ([#17](https://github.com/amit-t/ai-devkit/issues/17)) ([5e5ad36](https://github.com/amit-t/ai-devkit/commit/5e5ad361104e51cc8141f9bbf315110099d90d23))
* **version-check:** recover devkit clone when DEVKIT_CLONE env unset ([#17](https://github.com/amit-t/ai-devkit/issues/17)) ([02bd1bf](https://github.com/amit-t/ai-devkit/commit/02bd1bf885bc022af8cfd9007de256649936f444))
* **versioning:** harden ttl validation against non-numeric cache values ([08ac33f](https://github.com/amit-t/ai-devkit/commit/08ac33fda22d23c9de40942b4a7443ca947dd505))
* **versioning:** wire bootstrap nag into _wb_versioncheck + cover non-numeric ttl ([96f30c3](https://github.com/amit-t/ai-devkit/commit/96f30c368b2fd041a0c5e8567320db15413cdb2a))

## [1.5.0](https://github.com/amit-t/ai-devkit/compare/v1.4.0...v1.5.0) (2026-06-06)


### Features

* **init:** add Workbench Lite bootstrap with Ralph Devin setup

## [1.4.0](https://github.com/amit-t/ai-devkit/compare/v1.3.1...v1.4.0) (2026-06-01)


### Features

* add init.auto.wb / join.auto.wb / update.auto.wb for test-automation workbench ([61446dc](https://github.com/amit-t/ai-devkit/commit/61446dc17be6de896373a8147b57ec29db46b37b))
* add init.auto.wb / join.auto.wb / update.auto.wb for test-automation workbench ([99952d7](https://github.com/amit-t/ai-devkit/commit/99952d768ff0260de0d89438606a361f0bbcb47a))
* **init,join:** wire wb.graphify into init.wb and join.wb prompts ([#27](https://github.com/amit-t/ai-devkit/issues/27)) ([f7d1761](https://github.com/amit-t/ai-devkit/commit/f7d1761747b6eb045dec69f409ac85fe586e600a))
* **join.auto.wb:** pre-flight repo access check ([4309834](https://github.com/amit-t/ai-devkit/commit/430983479736cd72d4914f644ece19a2c4b09d58))
* **join.auto.wb:** pre-flight repo access check ([186a61a](https://github.com/amit-t/ai-devkit/commit/186a61acbb2a1842a1def24681b3f593e90d20ae))
* **orgs:** discover orgs dynamically from `gh api user/orgs` ([fa956d8](https://github.com/amit-t/ai-devkit/commit/fa956d8fe530d326753c8b4de1910ad77863b1b0))
* **orgs:** discover orgs dynamically from `gh api user/orgs` ([16c3163](https://github.com/amit-t/ai-devkit/commit/16c31631a9ad4d8d9f55232821e0611be2ad18ff))


### Bug Fixes

* **update.wb:** resolve version nag against wb root, not invocation cwd ([#26](https://github.com/amit-t/ai-devkit/issues/26)) ([732d05b](https://github.com/amit-t/ai-devkit/commit/732d05b66342b2af6eb9948ed8a95898c7648823))

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
