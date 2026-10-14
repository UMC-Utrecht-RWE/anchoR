# Stress test: `pregnancy_window_engine()`

The stress test measures how long `pregnancy_window_engine()` takes per input
row, so we can predict its cost on real study sizes. The original row-by-row
engine cost **0.9–1.7 ms per row** (15–28 minutes per million rows). The
current engine costs **about 0.002 ms per row** (2–3 seconds per million
rows), as long as the machine has enough free memory.

## Purpose

`pregnancy_window_engine()` (in `R/pregnancy_window.R`) builds the time
windows for the four episode-based constructors: `in_current_pregnancy`,
`in_prior_pregnancy`, `in_current_and_prior` and `outside_all_pregnancy`.
It first ran over `window_dt` in plain R, one row at a time, which made it the
bottleneck of the windowing step. It now stacks every row's episodes into one
table and works on whole columns. The test checks that it stays fast, and
isolates it from everything else (DuckDB, parquet I/O, selectors).

The test lives in
[`tests/testthat/test_stress-pregnancy-window.R`](../tests/testthat/test_stress-pregnancy-window.R).

## How to run it

The test is opt-in: it only runs when `ANCHOR_STRESS_TESTS` is set to `true`.
Run it from the root of the anchoR repo.

From an R session:

```r
Sys.setenv(ANCHOR_STRESS_TESTS = "true")
# Optional: choose the window_dt sizes (default "1000,5000,20000")
Sys.setenv(ANCHOR_STRESS_SIZES = "1000,5000,20000")

devtools::test(filter = "stress-pregnancy-window")
```

From a terminal:

```bash
ANCHOR_STRESS_TESTS=true ANCHOR_STRESS_SIZES=1000,5000,20000 \
  Rscript -e 'devtools::test(filter = "stress-pregnancy-window")'
```

| Setting               | Default              | What it does                                              |
| --------------------- | -------------------- | --------------------------------------------------------- |
| `ANCHOR_STRESS_TESTS` | unset (test skipped) | Set to `true` to run the test.                            |
| `ANCHOR_STRESS_SIZES` | `1000,5000,20000`    | Comma-separated list of `window_dt` row counts to time.   |

Use `filter = "stress-pregnancy-window"` so only this file runs. Without the
filter, the whole suite runs as well.

## What it does

For each size in `ANCHOR_STRESS_SIZES`, the test builds a synthetic
`window_dt` and times the engine once for each of the four episode modes. The
seed is fixed (`1026`), so reruns use identical data.

1. **Builds synthetic data.**
    - Persons = size ÷ 5, with 5 variables each, so the row count equals the
      size.
    - Each person has 0–4 non-overlapping episodes (weights 10% / 40% / 30% /
      15% / 5%), each 200–300 days long, with 60–700 day gaps between them,
      starting in 2015–2018.
    - T0 is spread over 2016–2022, so rows land inside an episode, between
      episodes, or before or after all of them.
    - Window settings: anchor bounds T0 − 730 to T0 + 365 days, ±7 days
      around each episode start and end, `cap_start_to_episode = TRUE`.
2. **Shapes it like production.** Episodes are nested with the real
   `nest_episodes_onto_population()`, then cross-joined with the metadata.
   This is the same input `define_window()` passes to a constructor.
3. **Times the engine.** It calls `pregnancy_window_engine()` with `CURRENT`,
   `PRIOR`, `CURRENT_AND_PRIOR` and `OUTSIDE_ALL`. Each call is timed with
   `system.time()` after a `gc()`, both wall clock and CPU time.
4. **Checks the output.** Each result must be a data.table, must not contain
   more person-variable pairs than the input, and must have no `NA` in
   `window_start` or `window_end`.
5. **Reports.** It prints a results table (one row per mode and size) and
   writes the results to `pregnancy_window_stress.csv` in R's `tempdir()`.

Only the engines are timed. Data generation, nesting, the cross join, DuckDB
and parquet I/O are not part of the measured time. The data generators live in
[`tests/testthat/helper-fixtures-stress.R`](../tests/testthat/helper-fixtures-stress.R).

## What to expect while running

- **Skipped by default.** A normal `devtools::test()` reports this test as
  `SKIP` with the reason `Set ANCHOR_STRESS_TESTS=true to run the stress
  test.` This is expected and keeps the regular suite fast.
- **No progress output.** Nothing is printed until every size and mode is
  done; the console sits on `ℹ Testing anchoR` in the meantime.
- **Duration.** The engine itself takes well under a second per 100k rows.
  Most of the run time goes into building the synthetic data and loading the
  package, so the default sizes finish in seconds.
- **Memory.** Large sizes need a few GB free. On a laptop with 8 GB of RAM
  and other apps open, 500k rows already made the machine swap (see
  [Results](#results-and-how-to-read-them)).
- **Pass/fail.** The test fails only on wrong output (see step 4 above), never
  on slowness. There is no timing threshold, so results do not depend on the
  machine being fast.

At the end you will see a block like this, followed by the testthat summary:

```text
pregnancy_window_engine stress results:
      episode_select input_rows output_rows seconds cpu_seconds ms_per_row
1:           CURRENT       1000         300   0.006       0.006      0.006
...
Saved to: /var/folders/.../RtmpXXXX/pregnancy_window_stress.csv
[ FAIL 0 | WARN 0 | SKIP 0 | PASS 33 ]
```

The CSV is in R's session temp folder, which is deleted when R exits. Copy it
somewhere else if you want to keep it.

## Results and how to read them

Run on 2026-10-14 (macOS laptop, 8 GB RAM), sizes `100000,500000`. This run
predates the `cpu_seconds` column:

| episode_select      | input rows | output rows | seconds | ms per row | est. min per 1M rows |
| ------------------- | ---------: | ----------: | ------: | ---------: | -------------------: |
| `CURRENT`           |    100,000 |      29,030 |   0.142 |    0.00142 |                0.024 |
| `PRIOR`             |    100,000 |     201,670 |   0.205 |    0.00205 |                0.034 |
| `CURRENT_AND_PRIOR` |    100,000 |     230,700 |   0.222 |    0.00222 |                0.037 |
| `OUTSIDE_ALL`       |    100,000 |     150,115 |   0.275 |    0.00275 |                0.046 |
| `CURRENT`           |    500,000 |     143,540 |  11.638 |    0.02328 |                0.388 |
| `PRIOR`             |    500,000 |     994,510 |  10.549 |    0.02110 |                0.352 |
| `CURRENT_AND_PRIOR` |    500,000 |   1,138,050 |   9.758 |    0.01952 |                0.325 |
| `OUTSIDE_ALL`       |    500,000 |     748,465 |  10.215 |    0.02043 |                0.341 |

For comparison, the original row-by-row engine on 2026-10-13 (macOS laptop)
took 0.84–1.70 ms per row at 500 and 2,000 rows, i.e. 14–28 minutes per
million rows.

Column meanings:

- **input_rows**: rows of `window_dt` (person × variable pairs) given to the
  engine.
- **output_rows**: candidate windows produced. One input row can produce zero,
  one or several windows, so this can be lower or higher than `input_rows`.
- **seconds**: wall-clock time for one engine call.
- **cpu_seconds**: CPU time (user + system) for the same call. When it is
  much lower than `seconds`, the engine was waiting on memory, not working.
- **ms_per_row**: `seconds` ÷ `input_rows`. This is the number to compare
  between runs and machines.
- **est_minutes_per_1M_rows**: `ms_per_row` scaled to one million input rows.

What the numbers say:

1. **About 600× faster than the row-by-row engine.** At 100k rows it costs
   0.0014–0.0028 ms per row, against 0.84–1.70 ms before.
2. **The 500k results are swapping, not the engine.** Five times more rows
   took about 50 times longer, but no step of the engine scales worse than a
   sort, so the cost per row should stay flat. The laptop was short on
   memory at the time: building the same 500k rows of test data in a
   separate run took 819 s of wall time but only 12 s of CPU time. Use
   `cpu_seconds` to check this on a new run.
3. **Modes that return more windows cost a little more.** `PRIOR` and
   `CURRENT_AND_PRIOR` produce 7–8× more output rows than `CURRENT` and take
   about 1.5× longer.
4. **Estimating a real study.** Rows = persons × episode variables, counted
   separately for each episode constructor used. For example, 200,000
   pregnancies × 5 episode variables = 1M rows, which takes a few seconds
   per constructor when memory is not the limit.

To estimate your own study, multiply its row count by the `ms_per_row` for
each constructor you use, then add the results together. Take `ms_per_row`
from a run where `cpu_seconds` is close to `seconds`.

## Caveats and next steps

- **Synthetic data.** Real episode counts per person, window settings and the
  mix of constructors change the absolute numbers. To check, run the test with
  sizes close to your study.
- **Single run per size.** Each mode is timed once, so expect about ±10%
  noise. Compare runs on the same machine.
- **Engine only.** The test does not cover `define_window()`'s cross join,
  writing windows to DuckDB, or the selector queries. Use `profvis` or
  debug-level logging on a full `anchor()` run for the whole picture.
- **Memory is now the limit.** Each person's episodes are nested into
  `window_dt` as a small table, so very large studies use a lot of memory
  before the engine starts. If that becomes a problem, the next step is to
  join a long episodes table on `person_id` instead of nesting it, or to run
  the step in DuckDB.
