# Sidekiq.cr Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.7.3] - 2024-08-28
### Fixed
- Fix undefined method errors in Chain#insert_*, thanks @Dakad (#123).

## [0.7.2] - 2023-04-19
### Fixed
- Fix version numbering mistake from 0.7.1 release.
- Fix some more ameba linter errors and ignore others.

### Changed
- Update dependencies and just fix the minimum required version of them
- Remove ameba from development dependencies but keep using it on CI.
- Adhere to https://keepachangelog.com/en/1.0.0/

## [0.7.1] - 2023-03-31
### Fixed
- Update kemal dependency [#112]

## [0.7.0] - 2021-04-01
### Fixed
- Works with Crystal 1.0

## [0.6.1] - 2017-05-09
### Fixed
- Updates for latest Crystal, Kemal versions

## [0.6.0] - 2016-09-08
### Added
- Implement `sidekiq_options` for Workers. [#3]

### Fixed
- Fixes for Crystal 0.19

## [0.5.0] - 2016-06-11
- Initial release.  See the wiki for how to [Get Started](https://github.com/mperham/sidekiq.cr/wiki/Getting-Started)!
