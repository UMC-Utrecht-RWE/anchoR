> [Engine](<Episode-Based Window Engine.md>) configured with `event_select = "CURRENT"`, `end_boundary = "ANCHOR"`: the window runs from the start of the episode containing the anchor date, up to the anchor itself.

Selects the single episode where `event_start <= anchor <= event_end` (if any); a person whose anchor date doesn't fall inside any episode produces no window and thus no result for that variable. Window: `[episode_start + start_offset, anchor + end_offset]`, the end boundary tracks the anchor date, not the episode's own end, which is what distinguishes this from [ANYTIME_CURRENT_PREG](ANYTIME_CURRENT_PREG.md).

Typical use: "has this concept occurred since the start of the person's current pregnancy, up to today."