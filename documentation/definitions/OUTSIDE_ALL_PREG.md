> [Engine](<Episode-Based Window Engine.md>) configured with `episode_select = "OUTSIDE_ALL"`: returns the gaps between *all* of a person's episodes, not any single one.

Searches `[anchor_start_col + anchor_start_offset, anchor_end_col + anchor_end_offset]` (order-independent the engine sorts the two resulting dates into a lower/upper bound) and returns every sub-range of that search window *not* covered by any episode, as zero, one, or several candidate windows. An episode always fences the gaps around it, even the one containing the anchor itself, so there is no gap starting exactly at the anchor if the anchor falls inside an ongoing episode.

Unlike the other three episode-based constructors, `OUTSIDE_ALL_PREG` does not read `before_start_episode_offset`/`after_start_episode_offset`/`before_end_episode_offset`/`after_end_episode_offset` at all there is no single selected episode for those to be relative to. Only `anchor_start_offset`/`anchor_end_offset` matter, and they define the search range itself rather than clamping toward an episode edge.

Typical use: "did this concept occur only outside of pregnancy" e.g. an obesity diagnosis recorded *during* a pregnancy episode is correctly excluded by this constructor, since that date isn't in any of the returned gap windows.
