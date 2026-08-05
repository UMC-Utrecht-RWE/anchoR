# anchoR documentation

Choose the shortest guide that matches the task.

## Start here

- **New to anchoR, or to this domain entirely?** [Quickstart.md](Quickstart.md) — no jargon assumed, five terms and one runnable example.
- [Standard windows](Tutorial_standard_windows.md): the complete fixed-anchor workflow.
- [Episode-based windows](Tutorial_pregnancy_windows.md): recurring start/end episodes.
- [Custom constructors and selectors](Tutorial_custom_constructors_and_selectors.md): define your own window shape or selection rule without editing anchoR.
- Installed equivalents: `vignette("standard-windows", package = "anchoR")` and `vignette("episode-windows", package = "anchoR")`.

## Input and output contracts

- [Population](Input_population.md)
- [Metadata](Input_metadata.md)
- [Concepts](Input_concepts.md)
- [Anchored output](Output_D4_StudyVariablesAnchored.md)
- [Result implementation walkthrough](get_anchor_result_walkthrough.md)

## Practical recipes

These are installed package vignettes and pkgdown articles:

| task                                              | vignette              |
| ------------------------------------------------- | --------------------- |
| Diagnose errors and unexpected cardinality        | `troubleshooting`     |
| Convert older BRIDGE-oriented metadata            | `metadata-migration`  |
| Compare selector semantics and edge cases         | `selector-cookbook`   |
| Design lookback, index, risk, and control windows | `multiple-windows`    |
| Define a project-specific window shape            | `custom-constructors` |
| Define a project-specific selection rule          | `custom-selectors`    |
| Query parquet and DuckDB concept stores           | `production-sources`  |
| Complete and impute wide results                  | `imputation`          |

For example:

```r
vignette("troubleshooting", package = "anchoR")
```

## Definitions

Short linked definitions live under [`definitions/`](definitions/). [Episode-Based Window Engine.md](<definitions/Episode-Based Window Engine.md>) is the canonical description of the episode-window border-offset formula — the four constructor pages and the episode tutorial summarize it but defer to that page. The historical pregnancy prototype under [`examples/pregnancy_examples.md`](examples/pregnancy_examples.md) is retained for design provenance only; use the current episode tutorial for supported metadata.

## Contributing to anchoR itself

Changing `R/`, `tests/`, or `inst/sql/` (rather than using anchoR from your own script)? See [`../CONTRIBUTING.md`](../CONTRIBUTING.md) for dev setup, the CI checks, and how to add a built-in constructor or selector.
