# Choosing Fast `anchor()` Settings

This guide shows how to use `tune_anchor_settings()` to compare the different ways that `anchor()` can process the same data. The function runs each requested setting, measures its run time, and reports the fastest successful combination. The anchoring result does not change; only the way the work is divided and published changes.

For details about the three processing modes, see [Tutorial_anchor_functions.md](Tutorial_anchor_functions.md).

## When should I use it?

Use `tune_anchor_settings()` before a large deap run when you do not know which settings will work best. Performance can depend on the number of people, concepts, variables, and selectors; the available memory; and whether output is on local, network, or cloud-mounted storage.

Use a representative sample of the real data. A very small or unusual sample may recommend settings that are not best for the complete deap run.

## A complete, runnable example

First, create the same three inputs used by `anchor()`:

```r
library(anchoR)
library(data.table)

population <- data.table(
  person_id = c("1", "2", "3"),
  T0 = as.Date(c("2024-01-01", "2024-01-01", "2024-06-01"))
)

metadata <- data.table(
  variable_id = c("latest_vaccine", "hospital_visits"),
  concept_id = c("VACCINE", "HOSPITAL"),
  constructor = "GENERIC",
  selector = c("LATEST", "COUNT"),
  start_offset = c(-365L, -90L),
  end_offset = 0L
)

concepts <- data.table(
  person_id = c("1", "1", "2", "3"),
  concept_id = c("VACCINE", "HOSPITAL", "HOSPITAL", "VACCINE"),
  date = as.Date(c("2023-10-01", "2023-12-10", "2023-12-20", "2024-03-01")),
  value = c("TRUE", "1", "1", "TRUE")
)
```

Create a directory for the benchmark output. `tempdir()` is suitable for this small example:

```r
benchmark_root <- file.path(tempdir(), "anchor-benchmark")
dir.create(benchmark_root, showWarnings = FALSE)
```

Now compare the three `by` modes. This search tries one set of `by = "variable"` settings, so it runs three combinations in total:

```r
tuning <- tune_anchor_settings(
  population = population,
  metadata = metadata,
  concepts = concepts,
  by_values = c("whole", "variable", "selector"),
  chunk_size_values = 1L,
  staging_mode_values = "memory",
  publish_values = "once",
  repeats = 1L,
  benchmark_hive_root = benchmark_root
)
```

Every combination writes to an isolated temporary hive below `benchmark_root`. That hive is removed when the run finishes. The input data and any production hive are not changed.

## Understanding the result

The function returns a list with three parts.

### `summary`: compare the settings

```r
tuning$summary
```

There is one row for each combination, ordered from fastest to slowest.

| column                | meaning                                 |
| --------------------- | --------------------------------------- |
| `by`                  | processing mode tested                  |
| `chunk_size`          | variables per chunk for variable mode   |
| `staging_mode`        | where variable-mode output was held     |
| `publish`             | when variable-mode output was published |
| `median_elapsed_secs` | median run time of successful repeats   |
| `n_success`           | number of successful repeats            |
| `n_failed`            | number of failed repeats                |

`chunk_size`, `staging_mode`, and `publish` are `NA` for `by = "whole"` and `by = "selector"` because those modes do not use these settings.

### `best`: get the recommendation

```r
tuning$best
```

This is the fastest row that succeeded at least once. The exact winner and run time will differ between computers and storage systems.

### `runs`: inspect individual runs and errors

```r
tuning$runs

# Show only failed runs.
tuning$runs[success == FALSE]
```

If every combination fails, `tuning$best` is `NULL`. Read the `error_message` column to find the cause before starting a production run.

## Running it for a deap

Use the deap's representative data and a dedicated directory on the same filesystem as the production hive:

```r
benchmark_root <- "/mnt/deap-storage/anchor-benchmark"
dir.create(benchmark_root, recursive = TRUE, showWarnings = FALSE)

tuning <- tune_anchor_settings(
  population = deap_population,
  metadata = deap_metadata,
  concepts = deap_concepts,
  episodes = deap_episodes, # Omit when episodes are not used.
  by_values = c("whole", "variable", "selector"),
  chunk_size_values = c(5L, 10L, 20L, 50L),
  staging_mode_values = c("memory", "disk"),
  publish_values = c("once", "per_chunk"),
  repeats = 3L,
  benchmark_hive_root = benchmark_root
)
```

Do not use the production hive itself as `benchmark_hive_root`. Use a separate directory on the same mounted filesystem. This measures realistic storage behavior without overwriting production output.

Start with `repeats = 1L` if the benchmark is expensive. Increase it when the fastest combinations have similar run times.

## Use the winning settings in production

Stop if every benchmark combination failed:

```r
if (is.null(tuning$best)) {
  stop("All benchmark combinations failed; inspect tuning$runs.")
}
```

Build the normal production call from the winning row:

```r
production_args <- list(
  population = deap_population,
  metadata = deap_metadata,
  concepts = deap_concepts,
  episodes = deap_episodes,
  anchor_hive_path = "/mnt/deap-storage/production-anchor-hive",
  by = tuning$best$by
)
```

The remaining settings apply only to `by = "variable"`. Add them only if that mode won:

```r
if (tuning$best$by == "variable") {
  production_args$chunk_size <- tuning$best$chunk_size
  production_args$staging_mode <- tuning$best$staging_mode
  production_args$publish <- tuning$best$publish
}

do.call(anchor, production_args)
```

The benchmark directory is not the production output. Final results are written to the `anchor_hive_path` supplied to `anchor()`.

## Practical advice

- Use data that resembles the real workload.
- Put `benchmark_hive_root` on the same filesystem as the production hive.
- Make sure the benchmark directory has enough free space.
- Review failed runs as well as the fastest result.
- Repeat the benchmark after large changes to the data, metadata, hardware, or storage environment.
- Remember that the publishing strategies have different failure behavior. Read [Tutorial_anchor_functions.md](Tutorial_anchor_functions.md) before changing the production publishing strategy.
