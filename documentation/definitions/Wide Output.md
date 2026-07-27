> `get_anchor_result(..., result_shape = "wide")`: one row per `person_id x T0` (or `x window_name`), with `value_<variable_id>` / `date_<variable_id>` columns.

Built by `dcast`-ing the [Long Output](<Long Output.md>) shape. By default (`cast_window = FALSE`) rows are keyed by `person_id + T0 + window_name`, casting only on `variable_id`; with `cast_window = TRUE`, rows collapse to one per `person_id + T0`, folding `window_name` into the column name instead (`value_<window_name>_<variable_id>`).

Wide output is unambiguous when the anchored result has no duplicate `person_id + T0 + window_name + variable_id` combination. Repeating a `variable_id` for distinct windows is supported. A selector that produces several records for the same cell (normally `ALL`) makes wide output ambiguous, and `get_anchor_result()` tells the caller to use `result_shape = "long"`.

Passing `population` to `get_anchor_result()` backfills population keys with no match and reattaches extra population columns. With `cast_window = TRUE` this gives one row per population key; with the default `cast_window = FALSE`, each key is crossed with requested or discovered window names. Missing result cells mean that variable produced no match for the row; `impute_missing = TRUE` can turn supported value cells into typed defaults (`FALSE`/`0`) instead of `NA`.
