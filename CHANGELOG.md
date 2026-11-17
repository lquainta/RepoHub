# Changelog

## [0.3.0](https://github.com/lquainta/RepoHub/compare/v0.2.0...v0.3.0) (2026-11-17)


### Features

* **app:** adapt the main window to narrow and wide sizes ([#166](https://github.com/lquainta/RepoHub/issues/166)) ([2aa53ea](https://github.com/lquainta/RepoHub/commit/2aa53ea62c6a3f4cb49fbcd15c3bef92aaaab358))
* **app:** notify about failing CI and review requests ([#142](https://github.com/lquainta/RepoHub/issues/142)) ([6d31c61](https://github.com/lquainta/RepoHub/commit/6d31c613a172438f6fe972ab7a89866dd274151a))
* **app:** pass automated accessibility audits and document the practice ([#151](https://github.com/lquainta/RepoHub/issues/151)) ([b04737d](https://github.com/lquainta/RepoHub/commit/b04737dddef86446bfd018835e27ff9d33c4060f))
* **app:** translate the app into Spanish ([#152](https://github.com/lquainta/RepoHub/issues/152)) ([f07d159](https://github.com/lquainta/RepoHub/commit/f07d159df99f0bdc40848b257daeb03bf3397a6a))
* push CI and pull request changes to the app from GitHub webhooks ([#143](https://github.com/lquainta/RepoHub/issues/143)) ([2983a44](https://github.com/lquainta/RepoHub/commit/2983a44a50b6ac58943518adf0a2b0b92572e900))
* report crashes and server errors to Sentry ([#148](https://github.com/lquainta/RepoHub/issues/148)) ([58b6093](https://github.com/lquainta/RepoHub/commit/58b6093eed1bd900e48261abece29d83862f2b78))
* sync groups and settings between Macs ([#144](https://github.com/lquainta/RepoHub/issues/144)) ([f7f3564](https://github.com/lquainta/RepoHub/commit/f7f356488da7369427f2c867a592118dbbfe2c87))


### Bug Fixes

* **app:** give the dashboard the window's spare width instead of the details pane ([#197](https://github.com/lquainta/RepoHub/issues/197)) ([26abd78](https://github.com/lquainta/RepoHub/commit/26abd787304a9b7fd5f8f4298de547ebff0e064c))
* **app:** show a clear error when the server is down or can't be reached ([#194](https://github.com/lquainta/RepoHub/issues/194)) ([275dea5](https://github.com/lquainta/RepoHub/commit/275dea53eebcc863fbe2d381e71c77586988cf44))
* **backend:** delete webhook events older than 30 days ([#195](https://github.com/lquainta/RepoHub/issues/195)) ([0f21ede](https://github.com/lquainta/RepoHub/commit/0f21ede370b55b97ba72491d7b7ccae1e8c725b7))
* **backend:** treat GitHub's 422 for an unknown ref as a branch without checks ([#182](https://github.com/lquainta/RepoHub/issues/182)) ([c10e5f1](https://github.com/lquainta/RepoHub/commit/c10e5f14128fa449a04320d95b46e8eace98e2a0))
* **backend:** use UTC for every database session ([#181](https://github.com/lquainta/RepoHub/issues/181)) ([1a94b8d](https://github.com/lquainta/RepoHub/commit/1a94b8d1b6cd52e586773a7e42b8d31ae2a8d806))


### Documentation

* add architecture diagrams that are checked against the code ([#156](https://github.com/lquainta/RepoHub/issues/156)) ([ba1af64](https://github.com/lquainta/RepoHub/commit/ba1af64aeb9ebac505ae7b28ec5159788fd16896))
* publish DocC documentation for RepoHubCore and the backend ([#157](https://github.com/lquainta/RepoHub/issues/157)) ([8d18318](https://github.com/lquainta/RepoHub/commit/8d18318594a28a4d4043461e47a54365eb5534b5))
* write the README: what RepoHub does, and how to build, run, and test it ([#158](https://github.com/lquainta/RepoHub/issues/158)) ([2c2452e](https://github.com/lquainta/RepoHub/commit/2c2452e72b47faff7d3151448e3f21c5bcd88f85))


### Tests

* **app:** count the UI tests' coverage in the app's coverage report ([#176](https://github.com/lquainta/RepoHub/issues/176)) ([4ec47c3](https://github.com/lquainta/RepoHub/commit/4ec47c3556c457421f5d536f0ca297a173d158f7))
* **app:** cover groups, branch cleanup failures, the Keychain store, and known apps ([#185](https://github.com/lquainta/RepoHub/issues/185)) ([5024a44](https://github.com/lquainta/RepoHub/commit/5024a4482c0dd21f5f894077a47ed483ee7a8c5b))
* **app:** cover the API client's mapping of every response ([#177](https://github.com/lquainta/RepoHub/issues/177)) ([080838e](https://github.com/lquainta/RepoHub/commit/080838e4c931d15e09bbb20e8847ed57bd61930b))
* **app:** drive the main user flows end to end with XCUITest ([#150](https://github.com/lquainta/RepoHub/issues/150)) ([37b52dd](https://github.com/lquainta/RepoHub/commit/37b52dd29b084529979fe22b8ace0651631aef7e))
* **app:** read the stubbed request body to the end of its stream ([#189](https://github.com/lquainta/RepoHub/issues/189)) ([45f6e8d](https://github.com/lquainta/RepoHub/commit/45f6e8d37d9889db36104acb82dbc3ea5add6640))
* **app:** snapshot key views in light, dark, English, and Spanish ([#153](https://github.com/lquainta/RepoHub/issues/153)) ([34ddf19](https://github.com/lquainta/RepoHub/commit/34ddf19a3aedd770d06e12ba4b27eb74aaec9f8a))
* **app:** snapshot the menu bar panel, dashboard table, Activity window, and error states ([#191](https://github.com/lquainta/RepoHub/issues/191)) ([fca89e3](https://github.com/lquainta/RepoHub/commit/fca89e3afcd19dcd47790bc2be1dbffda9572636))
* **backend:** cover every route's failures and paginate pull requests ([#154](https://github.com/lquainta/RepoHub/issues/154)) ([8124ab0](https://github.com/lquainta/RepoHub/commit/8124ab0f6a3dad15390423034cb895239e3ff808))
* **backend:** cover the API's edge cases, middleware, and error transports ([#183](https://github.com/lquainta/RepoHub/issues/183)) ([61f6040](https://github.com/lquainta/RepoHub/commit/61f60405d54eb39ca7fb5d798ee27d2f9e8247e4))
* **backend:** keep the rate-limit API test inside one minute window ([#169](https://github.com/lquainta/RepoHub/issues/169)) ([524a6c0](https://github.com/lquainta/RepoHub/commit/524a6c0cba9f66c04f01797a004b75a8edc8594d))
* **backend:** make sure integration tests run in CI, and locally in one step ([#155](https://github.com/lquainta/RepoHub/issues/155)) ([c9b97f4](https://github.com/lquainta/RepoHub/commit/c9b97f490274565baf78981672cf9c883aee29c8))
* **core:** cover the remaining error paths and fallbacks ([#178](https://github.com/lquainta/RepoHub/issues/178)) ([d4fd0a4](https://github.com/lquainta/RepoHub/commit/d4fd0a4319acdadc9c2adf13f6506c6b2f219e42))


### CI/CD

* **deps:** bump superfly/flyctl-actions/setup-flyctl from 1.5 to 1.6 in the actions-minor-and-patch group ([#192](https://github.com/lquainta/RepoHub/issues/192)) ([783dfc9](https://github.com/lquainta/RepoHub/commit/783dfc90d222d75ecfd17855c95239084efa2e0b))
* drop CodeQL results in dependency code before uploading ([#165](https://github.com/lquainta/RepoHub/issues/165)) ([5ae1c93](https://github.com/lquainta/RepoHub/commit/5ae1c931111469eec8182d1f17ead16599546c48))
* publish the macOS app as a DMG on each GitHub Release ([#167](https://github.com/lquainta/RepoHub/issues/167)) ([ba85dd9](https://github.com/lquainta/RepoHub/commit/ba85dd9e7812679e06a5ec921125157e5d2f6cc7))

## [0.2.0](https://github.com/lquainta/RepoHub/compare/v0.1.0...v0.2.0) (2026-10-22)


### Features

* add fetch, pull, and open actions with a Repository menu ([#111](https://github.com/lquainta/RepoHub/issues/111)) ([1f2d9c8](https://github.com/lquainta/RepoHub/commit/1f2d9c80ddb1bb99affd1defebe837d6b6b2e3b5))
* **app:** add a menu bar summary ([#126](https://github.com/lquainta/RepoHub/issues/126)) ([1046f0f](https://github.com/lquainta/RepoHub/commit/1046f0ffdb9097bb4de41ac5f4dea2dfbf98fe45))
* **app:** add a Settings window ([#119](https://github.com/lquainta/RepoHub/issues/119)) ([cf93915](https://github.com/lquainta/RepoHub/commit/cf939153bd92c80840fc367c9a4b3463222c3bf7))
* **app:** persist scan folders and repositories with SwiftData ([#102](https://github.com/lquainta/RepoHub/issues/102)) ([2c99643](https://github.com/lquainta/RepoHub/commit/2c996430fd72246052d6bd91f4707a3a6c280b6b))
* **app:** refresh statuses automatically when files change ([#117](https://github.com/lquainta/RepoHub/issues/117)) ([21f1959](https://github.com/lquainta/RepoHub/commit/21f1959b74e2839a7c1560ea8a0d91c89b43869a))
* **app:** search, quick filters, and repository groups ([#115](https://github.com/lquainta/RepoHub/issues/115)) ([192541b](https://github.com/lquainta/RepoHub/commit/192541b9324135f4eec67a7a954414c64ad88b3e))
* **app:** show repository status in a sortable dashboard table ([#109](https://github.com/lquainta/RepoHub/issues/109)) ([51100db](https://github.com/lquainta/RepoHub/commit/51100db633d4f2b4905c34032b2991fc83fcf8d4))
* **app:** sign in with GitHub through the device flow ([#138](https://github.com/lquainta/RepoHub/issues/138)) ([eaa2660](https://github.com/lquainta/RepoHub/commit/eaa2660e23afc72e1182540e9121972a11ef63e3))
* **backend:** add a readiness check for PostgreSQL and Redis ([#136](https://github.com/lquainta/RepoHub/issues/136)) ([0bb015c](https://github.com/lquainta/RepoHub/commit/0bb015cfee213f3cbcc1848e27609433b4fd98fd))
* **backend:** add GitHub sign-in, sessions, and API hardening ([#134](https://github.com/lquainta/RepoHub/issues/134)) ([3c70bc7](https://github.com/lquainta/RepoHub/commit/3c70bc74cf221b4a35ea5052aec10928d7302890))
* **backend:** add PostgreSQL persistence with Fluent models and migrations ([#116](https://github.com/lquainta/RepoHub/issues/116)) ([9d51056](https://github.com/lquainta/RepoHub/commit/9d5105688a45c60616e5edb14fd5dcd3f8c3c751))
* **backend:** cache GitHub API responses in Redis ([#132](https://github.com/lquainta/RepoHub/issues/132)) ([e6a73db](https://github.com/lquainta/RepoHub/commit/e6a73db5205156ca97c4c48167bc597e6a59236f))
* **backend:** write structured JSON logs with request IDs ([#135](https://github.com/lquainta/RepoHub/issues/135)) ([1e07ce9](https://github.com/lquainta/RepoHub/commit/1e07ce91175e19982039d0c680a1ce6c830ff3f0))
* **core:** add git status service with porcelain v2 parser ([#101](https://github.com/lquainta/RepoHub/issues/101)) ([7019610](https://github.com/lquainta/RepoHub/commit/701961026a6aab072df197c2bbeabefe58108662))
* find and safely delete stale branches ([#113](https://github.com/lquainta/RepoHub/issues/113)) ([d04292c](https://github.com/lquainta/RepoHub/commit/d04292cc230aa6cfe87aefe285a22783884902eb))
* scan folders for git repositories and list them in the app ([#103](https://github.com/lquainta/RepoHub/issues/103)) ([bf4f002](https://github.com/lquainta/RepoHub/commit/bf4f0027664130931302848951ad76c28a97e4ff))
* show changed files, branches, commits, remotes, and stashes for the selected repository ([#110](https://github.com/lquainta/RepoHub/issues/110)) ([c573e93](https://github.com/lquainta/RepoHub/commit/c573e93b5dc12eb3adffa5a69b1cd57d72de0931))


### Bug Fixes

* **core:** run blocking git process work on dedicated threads ([#107](https://github.com/lquainta/RepoHub/issues/107)) ([c33fb44](https://github.com/lquainta/RepoHub/commit/c33fb44bc84d9828f7ea69186e4c9a98f81e32b7))


### Documentation

* add architecture decision records ([#112](https://github.com/lquainta/RepoHub/issues/112)) ([ebebd24](https://github.com/lquainta/RepoHub/commit/ebebd2429b4e510f7d18bb4824b03ae3f7e359e8))
* add contributing guide with branch, commit, and PR conventions ([#84](https://github.com/lquainta/RepoHub/issues/84)) ([b94acac](https://github.com/lquainta/RepoHub/commit/b94acacb807bf5f8f5fb9046bce4370539fe7ec5))
* add the OpenAPI spec and generate the server and client from it ([#133](https://github.com/lquainta/RepoHub/issues/133)) ([2791805](https://github.com/lquainta/RepoHub/commit/279180592e89f219b1844a7d1f2fc2fd8fd6920f))
* design the backend database schema with an ERD ([#114](https://github.com/lquainta/RepoHub/issues/114)) ([3972579](https://github.com/lquainta/RepoHub/commit/3972579844d2105b57b90e20061ff6db24775bc1))


### Tests

* add UI test target and document testing strategy ([#97](https://github.com/lquainta/RepoHub/issues/97)) ([6dffaf0](https://github.com/lquainta/RepoHub/commit/6dffaf0a3110442c2f6a0ecd7e94e5e517ef8ea3))
* **core:** benchmark scanning and status parsing with time budgets ([#122](https://github.com/lquainta/RepoHub/issues/122)) ([27fbe20](https://github.com/lquainta/RepoHub/commit/27fbe20ad3ba06e339c2561572c0c97bbd2df29d))
* **core:** scan a tree of real repositories end to end ([#121](https://github.com/lquainta/RepoHub/issues/121)) ([9f5f552](https://github.com/lquainta/RepoHub/commit/9f5f552be0358ce2828fad0a4a76d786c87321f3))


### CI/CD

* add CODEOWNERS and PR title / linked-issue checks ([#86](https://github.com/lquainta/RepoHub/issues/86)) ([a060038](https://github.com/lquainta/RepoHub/commit/a060038f9a7a51219703acd9c3759d2c5b2f2b12))
* add CodeQL code scanning for Swift and GitHub Actions ([#106](https://github.com/lquainta/RepoHub/issues/106)) ([6f821ab](https://github.com/lquainta/RepoHub/commit/6f821abeb6ba7808ae7cf090d91bf1b348d0236c))
* add opt-in auto-merge for labeled and Dependabot PRs ([#89](https://github.com/lquainta/RepoHub/issues/89)) ([5541eb8](https://github.com/lquainta/RepoHub/commit/5541eb85b23ec9b4468aa3b2f10d4b77391fce61))
* back up the production database nightly and test restores weekly ([#146](https://github.com/lquainta/RepoHub/issues/146)) ([b448de0](https://github.com/lquainta/RepoHub/commit/b448de0612b8e7c7a8ba5fdbfa25bb5ebc6fd28b))
* build and test app, core, and backend on every PR and push to main ([#95](https://github.com/lquainta/RepoHub/issues/95)) ([b2eff23](https://github.com/lquainta/RepoHub/commit/b2eff2395788ce3af3df3f5e791ff9380e3215a4))
* deploy the backend to Fly.io ([#137](https://github.com/lquainta/RepoHub/issues/137)) ([87e19ba](https://github.com/lquainta/RepoHub/commit/87e19ba6422385bbaeebccb98fcdcb5d912d136d))
* **deps:** bump the actions-minor-and-patch group with 2 updates ([#127](https://github.com/lquainta/RepoHub/issues/127)) ([a14f305](https://github.com/lquainta/RepoHub/commit/a14f305feae218ea7463cb5dc697d23ce113b84c))
* **deps:** bump the actions-minor-and-patch group with 2 updates ([#128](https://github.com/lquainta/RepoHub/issues/128)) ([6136f8b](https://github.com/lquainta/RepoHub/commit/6136f8b526fbfb07bd93097b34d13a18c4b29db3))
* give CodeQL's Swift analysis 45 minutes ([#125](https://github.com/lquainta/RepoHub/issues/125)) ([3c81d99](https://github.com/lquainta/RepoHub/commit/3c81d991349877c3179b8e2fa27d192586674bcf))
* report code coverage to Codecov with a README badge ([#104](https://github.com/lquainta/RepoHub/issues/104)) ([b49b8db](https://github.com/lquainta/RepoHub/commit/b49b8dbf8c9386f9c0e0123bd60180d29905a927))
* require PR title and linked-issue checks on main ([#91](https://github.com/lquainta/RepoHub/issues/91)) ([006c3bc](https://github.com/lquainta/RepoHub/commit/006c3bc8bc765f81bea7948eef3361fcba03ea75))
* scan git history for secrets with Gitleaks ([#99](https://github.com/lquainta/RepoHub/issues/99)) ([44dede0](https://github.com/lquainta/RepoHub/commit/44dede0a131ee49204e0ea5ecd4a51ddd4ff05a9))
* version releases and write the changelog with release-please ([#130](https://github.com/lquainta/RepoHub/issues/130)) ([521461d](https://github.com/lquainta/RepoHub/commit/521461d403c47f4eb495a13d92f9fbe63031278b))
