# Long output

`get_anchor_result(..., result_shape = "long")` returns the persisted sparse selector results with columns `person_id`, `T0`, `variable_id`, `window_name`, `date`, and `value`.

There is no row when a window has no matching concept record. All built-in selectors except `ALL` return at most one row per output key. Supplying `population` does not filter, complete, or enrich long output; population handling applies only to wide output.
