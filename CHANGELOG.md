# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased]

### Added

### Changed

- `anchor_by_variable()` now opens one DuckDB connection and loads `concepts`
  once for the whole call instead of once per `variable_id`, and reuses the
  already-validated `population` table across variables instead of
  re-validating/re-copying it each time. Cuts redundant concepts scans and
  connection overhead for metadata with many standard-window variables.

### Removed

### Fixed

### Future Work

## [v1.4]

### Added

- `R/pregnancy_window.R` with four constructore for multi-events entryes.
- `documentation` Folder containing a more procise and extend documentation.

# List of releases
- unreleased: https://github.com/UMC-Utrecht-RWE/anchoR@main
- v1.4 https://github.com/UMC-Utrecht-RWE/anchoR@1.4
