> [Engine](<Episode-Based Window Engine.md>) configured with `episode_select = "OUTSIDE_ALL"`: returns the gaps between *all* of a person's episodes, not any single one.

Searches `[anchor_start_col + anchor_start_offset, anchor_end_col + anchor_end_offset]` (order-independent — the engine sorts the two resulting dates into a lower/upper bound) and returns every sub-range of that search window *not* covered by any episode, as zero, one, or several candidate windows. An episode always fences the gaps around it, even the one containing the anchor itself, so there is no gap starting exactly at the anchor if the anchor falls inside an ongoing episode.

Unlike the other three episode-based constructors, `OUTSIDE_ALL_PREG` does not read `before_start_episode_offset`/`after_start_episode_offset`/`before_end_episode_offset`/`after_end_episode_offset`, or `cap_start_to_episode`/`cap_end_to_episode`, at all — there is no single selected episode for those to be relative to. `anchor_start_offset`/`anchor_end_offset` define the search range itself here, rather than clipping a window built some other way. Every episode-based constructor also clips its output to that same `[anchor_start_col + anchor_start_offset, anchor_end_col + anchor_end_offset]` boundary (see "Step 4" in [Episode-Based Window Engine](<Episode-Based Window Engine.md>)), but for `OUTSIDE_ALL_PREG` that clip is always a no-op — the gaps it returns already satisfy the boundary by construction, since it's the same range they were searched within.

Typical use: "did this concept occur only outside of pregnancy" — e.g. an obesity diagnosis recorded *during* a pregnancy episode is correctly excluded by this constructor, since that date isn't in any of the returned gap windows.

> [!WARNING]
> **This constructor can never return a day inside any episode, including the current one.** Its search range is relative to the anchor (`T0`), not to the episode. When `T0` falls inside a pregnancy (e.g. a vaccination date at 28 weeks), the current pregnancy fences off everything from its `start_episode` onwards. The effective window then ends at `start_episode - 1`, and the lookback before `start_episode` is shorter than the offsets suggest. To get a window measured from the episode's start (e.g. "365 days before LMP", or one that reaches into the pregnancy, like "until LMP + 12 weeks"), use `in_current_pregnancy` with border offsets instead.

## Worked example: anchor inside the current pregnancy

One person with an earlier pregnancy, `[2025-03-01, 2025-06-15]`, and a current one, `[2025-12-01, 2026-09-01]`. `T0 = 2026-06-15` (28 weeks into the current pregnancy). Metadata: `anchor_start_offset = -365`, `anchor_end_offset = -1`.

```r
define_window(population, metadata, episodes = episodes)[, .(window_start, window_end)]
#>    window_start window_end
#> 1:   2025-06-16 2025-11-30
```

The search range is `[2025-06-15, 2026-06-14]` (`T0 - 365` to `T0 - 1`). It is then cut on both sides:

- the earlier pregnancy covers `2025-06-15`, so the gap starts the day after it ends, `2025-06-16`;
- the current pregnancy covers everything from `2025-12-01` to `T0 - 1`, so the gap ends the day before it starts, `2025-11-30`.

So the "365-day lookback" is really 168 days, all before the current pregnancy's start. The later `T0` falls in the pregnancy, the shorter it gets.
