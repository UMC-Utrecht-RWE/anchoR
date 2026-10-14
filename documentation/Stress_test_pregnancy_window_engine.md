# Stress test: `pregnancy_window_engine()`

The stress test measures how long `pregnancy_window_engine()` takes per input
row, so we can predict its cost on real study sizes. In the first measurement
it cost **0.9–1.7 ms per row**, which is **15–28 minutes per million rows**
for each episode constructor.

## Purpose

`pregnancy_window_engine()` (in `R/pregnancy_window.R`) builds the time
windows for the four episode-based constructors: `in_current_pregnancy`,
`in_prior_pregnancy`, `in_current_and_prior` and `outside_all_pregnancy`.
Unlike the rest of anchoR, where the heavy work runs in DuckDB or data.table,
this function loops over `window_dt` in plain R, one row at a time. That makes
it the most likely bottleneck in the windowing step. The test isolates it from
everything else (DuckDB, parquet I/O, selectors).

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
| `ANCHOR_STRESS_OLD_MAX_ROWS` | `20000`       | Largest size at which the old engine is also timed. Set to `0` to time only the new engine (e.g. for 1M rows). |

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
3. **Times both engines.** It calls the vectorized `pregnancy_window_engine()`
   and, for sizes up to `ANCHOR_STRESS_OLD_MAX_ROWS`, the original row-by-row
   `pregnancy_window_engine_old()`, with `CURRENT`, `PRIOR`,
   `CURRENT_AND_PRIOR` and `OUTSIDE_ALL`. Each call is timed (wall clock)
   with `system.time()` after a `gc()`.
4. **Checks the output.** Each result must be a data.table, must not contain
   more person-variable pairs than the input, and must have no `NA` in
   `window_start` or `window_end`. When the old engine runs too, both outputs
   must be identical.
5. **Reports.** It prints a results table (one row per engine, mode and
   size), a speed-up table (old seconds ÷ new seconds), and writes the
   results to `pregnancy_window_stress.csv` in R's `tempdir()`.

Only the engines are timed. Data generation, nesting, the cross join, DuckDB
and parquet I/O are not part of the measured time. The data generators live in
[`tests/testthat/helper-fixtures-stress.R`](../tests/testthat/helper-fixtures-stress.R).

Correctness of the new engine is covered separately, in the default test
suite, by
[`test_pregnancy_window_engine_equivalence.R`](../tests/testthat/test_pregnancy_window_engine_equivalence.R).
It compares old and new on every combination of set/unset border offsets,
caps, anchor clips, a second anchor column, overlapping episodes, empty input
and the inverted-offset errors.

## What to expect while running

- **Skipped by default.** A normal `devtools::test()` reports this test as
  `SKIP` with the reason `Set ANCHOR_STRESS_TESTS=true to run the stress
  test.` This is expected and keeps the regular suite fast.
- **No progress output.** Nothing is printed until every size and mode is
  done; the console sits on `ℹ Testing anchoR` in the meantime.
- **Duration.** Each size runs all four modes, about 5 ms per row in total.
  Add a few seconds for loading the package.

  | Sizes                       | Approximate run time |
  | --------------------------- | -------------------- |
  | `500,2000`                  | ~15 s                |
  | `1000,5000,20000` (default) | ~2 min               |
  | `1000,10000,50000`          | ~5 min               |
  | `100000`                    | ~9 min               |

- **Memory.** Modest: the engine keeps one small data.table per output row
  until the final `rbindlist()`. 100k rows fits comfortably on a laptop.
- **Pass/fail.** The test fails only on wrong output (see step 4 above), never
  on slowness. There is no timing threshold, so results do not depend on the
  machine being fast.

At the end you will see a block like this, followed by the testthat summary:

```text
pregnancy_window_engine stress results:
      episode_select input_rows output_rows seconds ms_per_row est_minutes_per_1M_rows
1:           CURRENT        500         140   0.439      0.878                    14.6
...
Saved to: /var/folders/.../RtmpXXXX/pregnancy_window_stress.csv
[ FAIL 0 | WARN 0 | SKIP 0 | PASS 33 ]
```

The CSV is in R's session temp folder, which is deleted when R exits. Copy it
somewhere else if you want to keep it.

## Results and how to read them

Baseline run on 2026-10-13 (macOS laptop), sizes `500,2000`:

| episode_select      | input rows | output rows | seconds | ms per row | est. min per 1M rows |
| ------------------- | ---------: | ----------: | ------: | ---------: | -------------------: |
| `CURRENT`           |        500 |         140 |   0.439 |      0.878 |                 14.6 |
| `PRIOR`             |        500 |       1,030 |   0.750 |      1.500 |                 25.0 |
| `CURRENT_AND_PRIOR` |        500 |       1,170 |   0.852 |      1.704 |                 28.4 |
| `OUTSIDE_ALL`       |        500 |         810 |   0.422 |      0.844 |                 14.1 |
| `CURRENT`           |      2,000 |         610 |   1.817 |      0.908 |                 15.1 |
| `PRIOR`             |      2,000 |       3,640 |   3.005 |      1.502 |                 25.0 |
| `CURRENT_AND_PRIOR` |      2,000 |       4,250 |   3.316 |      1.658 |                 27.6 |
| `OUTSIDE_ALL`       |      2,000 |       2,985 |   1.850 |      0.925 |                 15.4 |

Column meanings:

- **input_rows**: rows of `window_dt` (person × variable pairs) given to the
  engine.
- **output_rows**: candidate windows produced. One input row can produce zero,
  one or several windows, so this can be lower or higher than `input_rows`.
- **seconds**: wall-clock time for one engine call.
- **ms_per_row**: `seconds` ÷ `input_rows`. This is the number to compare
  between runs and machines.
- **est_minutes_per_1M_rows**: `ms_per_row` scaled to one million input rows.

What the numbers say:

1. **Cost grows linearly with rows.** `ms_per_row` stayed the same when the
   input grew 4×, so the per-row figure can be used to extrapolate.
2. **The cost is R overhead, not computation.** Each row pays for
   `window_dt[i]`, building small data.tables, `rbindlist()` and `cbind()`.
   The date arithmetic itself is negligible.
3. **Modes that return more windows are slower.** `PRIOR` and
   `CURRENT_AND_PRIOR` produce about 2× more output rows and take about 1.7×
   longer than `CURRENT` and `OUTSIDE_ALL`.
4. **Estimating a real study.** Rows = persons × episode variables, counted
   separately for each episode constructor used. For example, 200,000
   pregnancies × 5 episode variables = 1M rows, which takes about 15–28
   minutes per constructor. If all four constructors are used, that is
   roughly an hour before DuckDB starts.

To estimate your own study, multiply its row count by the `ms_per_row` for
each constructor you use, then add the results together.

## Caveats and next steps

- **Synthetic data.** Real episode counts per person, window settings and the
  mix of constructors change the absolute numbers. To check, run the test with
  sizes close to your study.
- **Single run per size.** Each mode is timed once, so expect about ±10%
  noise. Compare runs on the same machine.
- **Engine only.** The test does not cover `define_window()`'s cross join,
  writing windows to DuckDB, or the selector queries. Use `profvis` or
  debug-level logging on a full `anchor()` run for the whole picture.
- **Next step: vectorize the engine.** Replace the per-row loop with a
  data.table join of windows to episodes on `person_id` (or one DuckDB
  query). That should bring 1M rows down to seconds. Use this test to measure
  the speed-up and the existing tests in
  `tests/testthat/test_pregnancy_window.R` to confirm the results are
  unchanged.
