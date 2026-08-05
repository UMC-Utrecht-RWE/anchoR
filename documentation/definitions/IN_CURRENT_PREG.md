> [Engine](<Episode-Based Window Engine.md>) configured with `episode_select = "CURRENT"`: window(s) built from the one episode containing the anchor date, if any.

Selects the single episode where `start_episode <= anchor <= end_episode` (using the row's `anchor_start_col` value, `T0` by default, as the anchor, via [classify_episodes()](<Episode-Based Window Engine.md>)). A person whose anchor date doesn't fall inside any episode produces no window and thus no result for that variable.

That one episode's window(s) come from the border-offset formula in [Episode-Based Window Engine](<Episode-Based Window Engine.md>): `before_start_episode_offset`/`after_start_episode_offset` relative to `start_episode`, `before_end_episode_offset`/`after_end_episode_offset` relative to `end_episode`. Depending on how many sides of each pair are set, this produces one shared window, one region, or two independent regions see that page for the full rule and worked examples.

Two common shapes:
- **Anytime during the current episode**: pin both edges to the episode's own bounds, `before_start_episode_offset = after_start_episode_offset = before_end_episode_offset = after_end_episode_offset = NA_real_` (neither pair set → the unshifted episode span becomes the window).
- **Since the start of the current episode, up to the anchor**: this constructor alone always windows relative to the *episode's own* `start_episode`/`end_episode`, never the anchor directly use `IN_CURRENT_PREG` together with a `GENERIC` variable anchored at `T0` if you need "up to today" rather than "up to the episode's end."

`anchor_start_offset`/`anchor_end_offset` are required metadata columns for this constructor (shared with `IN_PRIOR_PREG`/`IN_CURRENT_AND_PRIOR`) but are not read by `IN_CURRENT_PREG`'s own window math; they only matter for `OUTSIDE_ALL_PREG`.
