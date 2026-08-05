> `pregnancy_window_engine()`: the shared implementation behind all four episode-based [constructors](Constructor.md). This page is the **canonical** description of how it turns a person's episodes into windows the four constructor pages ([IN_CURRENT_PREG](IN_CURRENT_PREG.md), [IN_PRIOR_PREG](IN_PRIOR_PREG.md), [IN_CURRENT_AND_PRIOR](IN_CURRENT_AND_PRIOR.md), [OUTSIDE_ALL_PREG](OUTSIDE_ALL_PREG.md)) and the [episode-window tutorial](../Tutorial_pregnancy_windows.md)/vignette only say what's specific to each one and link back here for the formula itself.

Every episode-based constructor is this one engine, pre-configured with an `episode_select` (`"CURRENT"`, `"PRIOR"`, `"CURRENT_AND_PRIOR"`, or `"OUTSIDE_ALL"`). Adding a new named shape later means adding a short wrapper around this engine, not a new bespoke implementation.

Episodes come from the [Episodes](Episodes.md) input table, nested onto [Population](Population.md) internally (one small `data.table(start_episode, end_episode)` per person, in a `.episodes` list-column) before any constructor runs a caller only ever deals with the flat `episodes` table.

There are two independent steps: **which episode(s) are selected**, then **where each selected episode's window(s) sit**.

## Step 1: classifying episodes relative to the anchor

`classify_episodes()` labels every one of a person's episodes as `"current"`, `"prior"`, `"future"`, or `NA`, relative to that row's anchor date (`anchor_start_col`, `T0` by default):

- **Current**: the episode containing the anchor (`start_episode <= anchor <= end_episode`). A person's episodes are assumed not to overlap, so there is at most one.
- If a current episode exists, **prior**/**future** are relative to *that episode's own bounds*: an episode ending before the current episode's start is prior; one starting after the current episode's end is future.
- **If there is no current episode**, prior/future fall back to being relative to the anchor itself instead: ended before the anchor is prior, starts after the anchor is future.
- An episode that fits none of the above (e.g. one that overlaps the current episode despite the no-overlap assumption) is classified `NA` and is never selected by anything.

`IN_CURRENT_PREG` selects `"current"`; `IN_PRIOR_PREG` selects every `"prior"` episode (zero, one, or many); `IN_CURRENT_AND_PRIOR` selects both. `"future"` is computed but not currently used by any built-in constructor.

## Step 2: building a window from one selected episode the border-offset formula

Once an episode is selected, `episode_windows()` turns it into one or two candidate windows using four offset columns, in two independent pairs:

- **Start pair**: `before_start_episode_offset` / `after_start_episode_offset`, both relative to that episode's own `start_episode`.
- **End pair**: `before_end_episode_offset` / `after_end_episode_offset`, both relative to that episode's own `end_episode`.

Each side is read as `edge + offset` (`0` means "exactly on the edge"; `NA` means "this side isn't set"). What a pair does depends on how many of its two sides are set:

| pair state               | contributes                                                                                             |
| ------------------------ | ------------------------------------------------------------------------------------------------------- |
| **both sides `NA`**      | the edge itself, unshifted, to the *shared* window                                                      |
| **exactly one side set** | `edge + that offset` to the *shared* window (no ambiguity there's only one value)                       |
| **both sides set**       | its own self-contained region, `[edge + before_offset, edge + after_offset]`, **not** the shared window |

A pair with both sides set must not be inverted: `before_*_offset` later than `after_*_offset` is an error (`` `before_start_episode_offset` must not be later than `after_start_episode_offset` ``, and the equivalent for the end pair).

Putting the two pairs together, per episode:

- **Neither pair fully specified**: one shared window, `[start_episode + start_side, end_episode + end_side]`, using whichever single offset each pair has set (or the unshifted edge if a pair has neither side set).
- **Exactly one pair fully specified**: *only that pair's region* is emitted. The other pair whether it's fully unset or only has one side set contributes nothing at all.
- **Both pairs fully specified**: two independent regions, one per pair, `[start_episode + before_start_episode_offset, start_episode + after_start_episode_offset]` and `[end_episode + before_end_episode_offset, end_episode + after_end_episode_offset]`.

Worked examples, episode `[2025-01-07, 2025-05-07]`:

| `before_start` | `after_start` | `before_end` | `after_end` | result                                                                                                                                     |
| -------------- | ------------- | ------------ | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `NA`           | `NA`          | `NA`         | `NA`        | one window, `[2025-01-07, 2025-05-07]` (the episode's own unshifted span)                                                                  |
| `0`            | `NA`          | `NA`         | `0`         | one window, `[2025-01-07, 2025-05-07]` (each edge pinned to itself)                                                                        |
| `-7`           | `NA`          | `-7`         | `NA`        | one window, `[2024-12-31, 2025-04-30]` (both edges shifted 7 days earlier)                                                                 |
| `-7`           | `7`           | `NA`         | `NA`        | one region, `[2024-12-31, 2025-01-14]` a 15-day window around the episode's *start* only; the end pair is unset, so it contributes nothing |
| `-7`           | `7`           | `-7`         | `7`         | two regions: `[2024-12-31, 2025-01-14]` and `[2025-04-30, 2025-05-14]`                                                                     |
| `0`            | `0`           | `0`          | `0`         | two single-day regions: `[2025-01-07, 2025-01-07]` and `[2025-05-07, 2025-05-07]`                                                          |

If a selected episode's engine call produces two regions (both pairs fully specified) or a constructor selects several episodes (e.g. `IN_PRIOR_PREG` with two prior episodes), each region/episode becomes its own candidate [Window](Window.md) row. See "Multiple candidate windows" in the tutorial for how the [Selector](Selector.md) then treats them.

## `OUTSIDE_ALL_PREG`: a different job entirely

`OUTSIDE_ALL` doesn't select or window individual episodes it finds the gaps *between all* of a person's episodes inside `[anchor_start_col + anchor_start_offset, anchor_end_col + anchor_end_offset]`, and returns each gap as its own candidate window. The four border offsets above are not read at all for this constructor. An episode always fences the gaps around it, even the one containing the anchor itself, so there is no gap starting exactly at the anchor if the anchor falls inside an ongoing episode. See [OUTSIDE_ALL_PREG](OUTSIDE_ALL_PREG.md) for the search-range mechanics.
