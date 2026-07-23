> `event_window_engine()`: the shared implementation behind all four episode/pregnancy [constructors](Constructor.md), answering "which episode(s) matter, and where do the window boundaries sit relative to them?"

Every event-based constructor is this one engine, pre-configured with an `event_select` (`"PRIOR"`, `"CURRENT"`, or `"OUTSIDE_ALL"`) and, for `"CURRENT"`, an `end_boundary` (`"event_END"` or `"ANCHOR"`). Adding a new named shape later means adding a five-line wrapper around this engine, not a new bespoke implementation.

Unlike `T0`, episodes are a *list* per person, so they don't fit as a plain [Population](Population.md) column, they're nested instead: one population row still per person, with a list-column (named by metadata's `event_col`) holding that person's own small table of `event_start`/`event_end` rows.

For `"PRIOR"` / `"CURRENT"`, the engine selects matching episodes (`event_end < anchor`, or `event_start <= anchor <= event_end`), then computes `window_start = episode_start + start_offset` and `window_end` as either `episode_end + end_offset` or `anchor + end_offset` depending on `end_boundary`, optionally capped by [`end_cap_offset`](<End Cap Offset.md>). For `"OUTSIDE_ALL"`, it instead finds the gaps *between* all of a person's episodes inside `[anchor + start_offset, anchor + end_offset]`, an episode always fences the gaps around it, even the one containing the anchor itself.

`IN_PRIOR_PREG` and `OUTSIDE_ALL_PREG` can produce more than one candidate [Window](Window.md) per person for the same variable. The [Selector](Selector.md) aggregates joined matches under the same output key; `ALL` can return several rows. Candidate windows are not deduplicated, so overlapping windows can match one concept event more than once.
