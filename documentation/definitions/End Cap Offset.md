> Optional metadata column `end_cap_offset`, used only by [[IN_PRIOR_PREG]]: caps a prior-episode window's end at `episode_start + end_cap_offset`, if that's earlier than the otherwise-computed `episode_end + end_offset`.

Implemented as `window_end <- pmin(window_end, episode_start + end_cap_offset)`. 

This is what lets the same constructor express both "anytime during a prior pregnancy" (`end_cap_offset` unset) and "only the first N days of a prior pregnancy" (`end_cap_offset = N`) the difference lives entirely in metadata, not in new R code.

Defaults to `NA_real_` when absent from metadata, which the engine treats as "no cap."