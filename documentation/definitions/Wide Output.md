> `get_anchor_result(..., result_shape = "wide")`: one row per `person_id x T0` (or `x window_name`), with `value_<variable_id>` / `date_<variable_id>` columns.

Built by `dcast`-ing the [Long Output](<Long Output.md>) shape. By default (`cast_window = FALSE`) rows are keyed by `person_id + T0 + window_name`, casting only on `variable_id`; with cast_window `= TRUE`, rows collapse to one per `person_id + T0`, folding `window_name` into the column name instead (`value_<window_name>_<variable_id>`).

Wide output is only unambiguous when `metadata$variable_id` is unique in the requested metadata *and* the anchored result has no duplicate `person_id + T0 + window_name + variable_id` combination, a `variable_id` that can produce several rows (e.g. the `ALL` [Selector](Selector.md), or several windows without `cast_window`) makes wide output ambiguous and `get_anchor_result()` errors, telling the caller to use `result_shape = "long"` instead.

Passing `population` to `get_anchor_result()` backfills a row for every population key with no match at all, so wide output always has a predictable, population-sized number of rows. Missing `value_<variable_id>` / `date_<variable_id>` cells mean that variable produced no match for that row; `impute_missing = TRUE` can turn those into typed defaults (`FALSE`/`0`) instead of `NA`.
