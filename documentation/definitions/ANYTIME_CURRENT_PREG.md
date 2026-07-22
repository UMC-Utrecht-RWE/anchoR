> [Engine](<Episode-Based Window Engine.md>) configured with `event_select = "CURRENT"`, `end_boundary = "event_END"`: the window spans the entire episode containing the anchor date (not just up to the anchor).

Selects the single episode where `event_start <= anchor <= event_end`. Window: `[episode_start + start_offset, episode_end + end_offset]` unlike [SINCE_START_CURRENT_PREG](SINCE_START_CURRENT_PREG.md), the end boundary is the episode's own end (plus offset), so records *after* the anchor date but still inside the same episode are included.

Typical use: "has this concept occurred at any point during the person's current pregnancy," including a grace period after it ends via a positive `end_offset`.