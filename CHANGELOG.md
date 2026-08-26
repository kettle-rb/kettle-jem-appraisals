# Changelog

[![SemVer 2.0.0][📌semver-img]][📌semver] [![Keep-A-Changelog 1.0.0][📗keep-changelog-img]][📗keep-changelog]

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog][📗keep-changelog],
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html),
and [yes][📌major-versions-not-sacred], platform and engine support are part of the [public API][📌semver-breaking].
Please file a bug if you notice a violation of semantic versioning.

[📌semver]: https://semver.org/spec/v2.0.0.html
[📌semver-img]: https://img.shields.io/badge/semver-2.0.0-FFDD67.svg?style=flat
[📌semver-breaking]: https://github.com/semver/semver/issues/716#issuecomment-869336139
[📌major-versions-not-sacred]: https://tom.preston-werner.com/2022/05/23/major-version-numbers-are-not-sacred.html
[📗keep-changelog]: https://keepachangelog.com/en/1.0.0/
[📗keep-changelog-img]: https://img.shields.io/badge/keep--a--changelog-1.0.0-FFDD67.svg?style=flat

## [Unreleased]

### Added

### Changed

- [kc] kettle-jem/template: updated 17 project files:
  - code and tests (1)
  - configuration (1)
  - dependencies (8)
  - documentation (2)
  - other (4)
  - workflows (1)

- [kc] kettle-jem/prepare: updated 34 project files:
  - code and tests (1)
  - configuration (1)
  - dependencies (30)
  - other (2)

### Deprecated

### Removed

### Fixed

### Security

## [0.1.1] - 2026-08-08

- TAG: [v0.1.1][0.1.1t]
- COVERAGE: 93.38% -- 734/786 lines in 13 files
- BRANCH COVERAGE: 77.14% -- 189/245 branches in 13 files
- 89.55% documented

### Added

- Added support for JRuby 10.1 and TruffleRuby 34.0.

- kettle-jem-template-20260720-005 - README Support & Community links now
  include RubyForum.
- kettle-jem-template-20260726-001 - Projects now include YARD lint
  configuration and documentation dependencies so documentation issues fail
  before generated docs are refreshed.
- kettle-jem-template-20260727-001 - Spec harness documentation now lists the
  RSpec helpers provided by `kettle-test`.

### Changed

- The `kettle-jem-appraisals` executable now supports `-v` / `--version` and
  prints a standard startup header on normal runs.
- Retemplated project metadata and CI/development automation with `kettle-jem` v7.0.0.

- kettle-jem-template-20260716-002 - Gemspecs now ship fewer repository-only
  files, reducing package noise for downstream packagers.
- kettle-jem-template-20260720-002 - Development Gemfiles now use the released
  `tree_sitter_language_pack` gem 1.13.3 or newer by default.
- kettle-jem-template-20260725-002 - Version specs now use `anonymous_loader` to
  cover `version.rb` without redefining constants, or are removed when version
  specs are not managed for the project.
- kettle-jem-template-20260728-001 - Generated Ruby workflows now use clearer
  setup-ruby-flash planning and can prepare appraisal-only jobs without
  installing the main Gemfile bundle.
- kettle-jem-template-20260801-001 - Generated README gem dashboard links now
  use ClickGems instead of BestGems.

- Align the supported Ruby and CI matrix with kettle-jem's Ruby 4.0 runtime requirement

- Align generated compatibility workflows with kettle-jem's Ruby 4.0 MRI and JRuby support

### Fixed

- Corrected OpenCollective funding metadata to use the `kettle-dev` collective.
- Updated generated project metadata links to use the `appraisal-rb` GitHub
  organization.
- Restored `docs/CNAME` so the generated documentation site keeps its custom domain.
- Unique generated appraisal entries now collapse onto standard `ruby-X-Y`
  appraisals, allowing kettle-jem templates to reuse badge-linked standard jobs
  instead of adding redundant framework-only appraisals.
- Ruby bucket detection now honors `.kettle-jem.yml` `ruby.test_minimum`, so
  collapsed appraisals do not target standard Ruby appraisals below the
  templated CI floor.
- Added a configurable standard appraisal collapse policy for projects whose
  matrixed dependency is required by the normal test suite; duplicate Ruby
  buckets can now collapse the newest compatible entry onto the standard
  `ruby-X-Y` appraisal while keeping older compatibility entries separate.
- Generated Appraisals can now include shared support gemfiles, so framework
  matrices that need adapter/setup dependencies do not have to use a separate
  kettle-jem framework matrix just to compose those dependencies.
- Replaced ad hoc gemspec parsing in the CLI with real gemspec loading and
  `Kettle::Jem::GemSpecReader` metadata from the active local `kettle-jem`.
- Generated Appraisals now strip the leading `gemfiles/` path segment so
  Appraisal2 resolves modular gemfiles from the correct root.
- Generated Appraisals no longer end with an extra blank line.
- Kept Ruby series detection compatible with released `kettle-jem` versions
  that do not yet export the appraisal minimum Ruby floor constant.

- Package configured license files in gem release file lists.

- kettle-jem-template-20260720-003 - StructuredMerge Git diff driver config now
  uses the installed `smorg-rb` driver command.
- kettle-jem-template-20260725-001 - Release pull request branches beginning
  with `feature/release` now run JRuby and TruffleRuby workflows.
- kettle-jem-template-20260726-002 - Generated version files now document their
  version namespace and constants, reducing warning-only YARD lint output.
- kettle-jem-template-20260726-003 - Coverage upload steps now treat Coveralls,
  QLTY, and Codecov as optional, so provider outages do not fail CI when local
  coverage thresholds still pass.
- kettle-jem-template-20260728-002 - Generated RuboCop configs now ignore the
  same `gemfiles/vendor/bundle` tree as `.gitignore`, so vendored dependency
  installs are not reported as project lint debt.
- kettle-jem-template-20260728-004 - Generated dep-heads workflows now use the
  setup-ruby Bundler install path for direct appraisal Gemfiles, avoiding rv
  lockfile parser failures on Git and path dependencies.
- kettle-jem-template-20260728-005 - VersionGem bootstrap now creates the
  missing canonical version spec when a project only has shim namespace version
  specs.
- kettle-jem-template-20260730-001 - Gemspec package file enumeration now runs
  relative to the gemspec directory, so release package contents stay correct
  even when the gemspec is loaded from another working directory.

- kettle-jem-template-20260801-002 - Generated RSpec helpers now normalize
  managed configuration block bindings structurally, preventing mixed block
  parameter names from producing invalid configuration after a merge.
- kettle-jem-template-20260801-003 - Generated project metadata and
  documentation now normalize configured underscore hostnames to valid
  hyphenated hostnames.
- kettle-jem-template-20260801-004 - Generated organization README logos now
  use GitHub's stable organization avatar endpoint instead of assuming a
  matching Galtzo-hosted asset exists.

- kettle-jem-template-20260802-001 - Devcontainer JSON files now merge as JSONC,
  preserving comments and trailing commas during template updates.

[Unreleased]: https://github.com/appraisal-rb/kettle-jem-appraisals/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/appraisal-rb/kettle-jem-appraisals/compare/43293712bb815238bc780aeacf3b284d95ab6633...v0.1.1
[0.1.1t]: https://github.com/appraisal-rb/kettle-jem-appraisals/releases/tag/v0.1.1
