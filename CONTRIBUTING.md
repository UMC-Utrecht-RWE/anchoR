# Contributing to anchoR

This is for anyone changing the package itself (`R/`, `tests/`, `inst/sql/`), not for someone using anchoR in their own analysis if that's you, `make_constructor()`/`make_selector()` (see `Tutorial_custom_constructors_and_selectors.md`) let you extend anchoR from your own script without touching this repo at all.

## Setup

```r
# From the repo root, in R:
install.packages(c("devtools", "roxygen2", "testthat", "lintr", "styler", "here", "knitr", "rmarkdown", "withr"))
devtools::install_deps(dependencies = TRUE)
devtools::load_all()   # loads the package as if installed, for interactive use
```

Requires R >= 4.0.0 (see `DESCRIPTION`). `Config/roxygen2/version` in `DESCRIPTION` pins the roxygen2 version documentation was generated with install that version if `devtools::document()` produces unexpected diffs.

## The inner loop

```r
devtools::load_all()                          # pick up R/ changes
testthat::test_file("tests/testthat/test_X.R") # run one test file while iterating
devtools::test()                               # full test suite
devtools::document()                           # regenerate NAMESPACE + man/ from roxygen comments
styler::style_pkg()                            # auto-fix code style
lintr::lint_package()                          # check for lint issues style doesn't auto-fix
devtools::check()                               # full R CMD check (build, tests, vignettes, docs)
```

Run `devtools::document()` after adding/changing any roxygen `#'` comment (new `@param`, a changed `@export`, a new function) `NAMESPACE` and `man/*.Rd` are generated, not hand-edited.

## What CI actually checks (`.github/workflows/`)

Four workflows run on every push/PR to `main`/`dev`:

| workflow             | what it does                                                | matrix                                          |
| -------------------- | ----------------------------------------------------------- | ----------------------------------------------- |
| `testthat.yaml`      | `devtools::test(stop_on_failure = TRUE)`                    | ubuntu, macOS, **Windows** each on R release    |
| `r_cmd_check.yaml`   | full `R CMD check`, warnings treated as failures            | ubuntu (release + oldrel-1), macOS, **Windows** |
| `code_quality.yaml`  | `lintr::lint_package()` and `styler::style_pkg(dry = "on")` | ubuntu only                                     |
| `test_coverage.yaml` | `covr::package_coverage()`, fails under 55%                 | ubuntu only                                     |

**The Windows leg matters more than it might look.** Because `.gitignore`/local dev environments are usually macOS or Linux, Windows-only bugs (different path separators, case-insensitive filesystem behavior, different temp-directory layout) tend to slip through local testing and only show up in CI, or worse, in a user's hands. `looks_like_glob()`'s regex bug (a bracket-expression escaping mistake that made it match *any* backslash, so it silently treated every Windows-style path as "looks like a glob" instead of erroring on a nonexistent one) is a concrete example it passed locally on macOS/Linux for a long time before it surfaced. If you're touching path handling, string escaping in regexes, or anything filesystem-adjacent, consider how it behaves with backslash path separators, not just forward slashes.

`.lintr` disables `object_usage_linter` and `indentation_linter`; everything else in `lintr`'s defaults applies.

## Adding to the package itself

- **A new built-in selector**: add `inst/sql/<name>.sql` (see the existing ones for the expected query shape join `population_windows AS w` to `concepts AS c`, project `person_id, T0, variable_id, window_name, value, date, n`), it's picked up automatically by name. Add tests in `tests/testthat/test_selectors.R`.
- **A new built-in constructor**: add an R function in `R/` built with `make_constructor()` (see `R/pregnancy_window.R` or `R/define_window.R`'s `generic_window` for the pattern), exported and named `<name>_window`. Add tests alongside the existing constructor tests.
- **A new window family sharing logic with an existing engine** (the way the four pregnancy constructors all wrap `pregnancy_window_engine()`): add a thin `make_constructor()` wrapper pre-configuring the shared engine with a new mode, rather than duplicating the engine's logic.

## Documentation

- `documentation/` and `vignettes/` currently duplicate some tutorials (e.g. `Tutorial_pregnancy_windows.md` / `episode-windows.Rmd`). Until that's consolidated, if you change externally-visible behavior, check both for a matching description, not just whichever one you remembered.
- `documentation/definitions/Episode-Based Window Engine.md` is the canonical description of the episode-window border-offset formula; other pages should link to it rather than re-deriving it.
- Update `CHANGELOG.md` under `## [Unreleased]` for anything a user of the package would notice (new/changed/removed behavior, bug fixes). Past release entries are never edited.

## Before opening a PR

1. `devtools::document()` (commit any resulting `NAMESPACE`/`man/` changes)
2. `styler::style_pkg()`
3. `devtools::test()` and `devtools::check()` locally `check()` catches vignette build failures and doc/code mismatches that `test()` alone won't
4. A `CHANGELOG.md` entry under `## [Unreleased]`, if the change is user-visible
