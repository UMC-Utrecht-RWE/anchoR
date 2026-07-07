> `get_anchor_result(..., result_shape = "long")`: one row per matched `person_id x T0 x variable_id x window_name`, with columns `date` and `value`.

This is the least ambiguous shape of the [[Anchored Result]] — every row is one match, so there's no reshaping to reconcile duplicates. It's the shape to prefer whenever a `variable_id` can legitimately produce more than one row per person (e.g. the `ALL` [[Selector]], or multiple [[Window Name|windows]] per variable that you don't want folded into columns).

Columns: `person_id`, `T0`, `variable_id`, `window_name`, `date`, `value`. Rows with no matching concept record in the requested window are simply absent.