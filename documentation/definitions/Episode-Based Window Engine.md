> `pregnancy_window_engine()`: the shared implementation behind all four episode-based [constructors](Constructor.md). This page is the **canonical** description of how it turns a person's episodes into windows — the four constructor pages ([IN_CURRENT_PREG](IN_CURRENT_PREG.md), [IN_PRIOR_PREG](IN_PRIOR_PREG.md), [IN_CURRENT_AND_PRIOR](IN_CURRENT_AND_PRIOR.md), [OUTSIDE_ALL_PREG](OUTSIDE_ALL_PREG.md)) and the [episode-window tutorial](../Tutorial_pregnancy_windows.md)/vignette only say what's specific to each one and link back here for the formula itself.

Every episode-based constructor is this one engine, pre-configured with an `episode_select` (`"CURRENT"`, `"PRIOR"`, `"CURRENT_AND_PRIOR"`, or `"OUTSIDE_ALL"`). Adding a new named shape later means adding a short wrapper around this engine, not a new bespoke implementation.

Episodes come from the [Episodes](Episodes.md) input table, nested onto [Population](Population.md) internally (one small `data.table(start_episode, end_episode)` per person, in a `.episodes` list-column) before any constructor runs; a caller only ever deals with the flat `episodes` table.

There are four independent steps: **which episode(s) are selected**, **where each selected episode's window(s) sit**, **optionally capping each window to that same episode's own real bounds**, and **clipping every resulting window to a hard anchor-relative boundary**.

## Step 1: classifying episodes relative to the anchor

`classify_episodes()` labels every one of a person's episodes as `"current"`, `"prior"`, `"future"`, or `NA`, relative to that row's anchor date (`anchor_start_col`, `T0` by default):

- **Current**: the episode containing the anchor (`start_episode <= anchor <= end_episode`). A person's episodes are assumed not to overlap, so there is at most one.
- If a current episode exists, **prior**/**future** are relative to *that episode's own bounds*: an episode ending before the current episode's start is prior; one starting after the current episode's end is future.
- **If there is no current episode**, prior/future fall back to being relative to the anchor itself instead: ended before the anchor is prior, starts after the anchor is future.
- An episode that fits none of the above (e.g. one that overlaps the current episode despite the no-overlap assumption) is classified `NA` and is never selected by anything.

`IN_CURRENT_PREG` selects `"current"`; `IN_PRIOR_PREG` selects every `"prior"` episode (zero, one, or many); `IN_CURRENT_AND_PRIOR` selects both. `"future"` is computed but not currently used by any built-in constructor.

## Step 2: building a window from one selected episode — the border-offset formula

Once an episode is selected, `episode_windows()` turns it into one or more candidate windows using four offset columns, in two pairs:

- **Start pair**: `before_start_episode_offset` (**outer** — points away from the episode, before it starts) / `after_start_episode_offset` (**inner** — points into the episode).
- **End pair**: `before_end_episode_offset` (**inner** — points into the episode) / `after_end_episode_offset` (**outer** — points away from the episode, after it ends).

Each side is read as `edge + offset` (`0` means "exactly on the edge"; `NA` means "this side isn't set"). Each pair's own contribution is decided independently, then a shared window (if triggered) is layered on top:

1. **A pair with both sides set** ("full") is always its own self-contained region, `[edge + before_offset, edge + after_offset]`, regardless of what the other pair does — it never joins a shared window, and it never suppresses the other pair's own contribution either. `before_offset` must not be later than `after_offset`, or that region would be inverted, which is an error.
2. A non-full pair whose only set side is its **outer** one (`before_start_episode_offset` alone, or `after_end_episode_offset` alone) pulls the *whole computation* into **shared-window mode**.
3. In shared-window mode, every non-full pair contributes exactly one point to a single shared window: its one set side if it has exactly one (regardless of whether that side is nominally "outer" or "inner"), or the unshifted edge if it has nothing set. A full pair sits this out — see rule 1 — so the shared window's edge on that side falls back to the unshifted edge too.
4. Outside shared-window mode, a non-full pair with only its **inner** side set (`after_start_episode_offset` alone, or `before_end_episode_offset` alone) forms its **own region** instead, missing side defaulting to `0`. A pair with nothing set contributes nothing (no region, no shared-window point).
5. If **neither pair has anything set**, the result is one window: the episode's own unshifted span, `[start_episode, end_episode]`.

Worked examples, episode `[2025-01-07, 2025-05-07]`:

| `before_start` | `after_start` | `before_end` | `after_end` | rule | result |
| --------------- | -------------- | ------------- | ------------- | ---- | ------ |
| `NA` | `NA` | `NA` | `NA` | (5) neither set | one window, `[2025-01-07, 2025-05-07]` |
| `0` | `NA` | `NA` | `0` | (2)+(3) both outer sides set alone | one shared window, `[2025-01-07, 2025-05-07]` (each edge pinned) |
| `-31` | `NA` | `NA` | `31` | (2)+(3) both outer | one shared window, `[2024-12-07, 2025-06-07]` |
| `NA` | `0` | `0` | `NA` | (4) both inner, no outer anywhere | two single-day regions, `[2025-01-07, 2025-01-07]` and `[2025-05-07, 2025-05-07]` |
| `NA` | `31` | `-31` | `NA` | (4) both inner | two regions, `[2025-01-07, 2025-02-07]` and `[2025-04-06, 2025-05-07]` |
| `-7` | `NA` | `-7` | `NA` | (2)+(3) start's outer side alone triggers shared mode; end's only side is its *inner* one, but it's used as a plain point anyway once shared mode is active | one shared window, `[2024-12-31, 2025-04-30]` |
| `NA` | `50` | `NA` | `NA` | (4) start's inner side alone, end pair fully empty | one region, `[2025-01-07, 2025-02-26]`; end contributes nothing |
| `-7` | `7` | `-7` | `7` | (1) both pairs full | two regions: `[2024-12-31, 2025-01-14]` and `[2025-04-30, 2025-05-14]` |
| `-7` | `7` | `-7` | `NA` | (1) start full, (4) end inner-alone, not shared (nothing triggers it) | two regions: start's own `[2024-12-31, 2025-01-14]` **and** end's own `[2025-04-30, 2025-05-07]` — the full pair does not suppress the other one |
| `NA` | `7` | `-7` | `7` | (1) end full, (4) start inner-alone | two regions: `[2025-01-07, 2025-01-14]` and `[2025-04-30, 2025-05-14]` |

The sixth row (`-7`/`NA`/`-7`/`NA`) is the case worth internalizing for shared-window mode: `before_end_episode_offset` is normally "inner" (rule 4, own region) — but because the *start* pair's outer side (`before_start_episode_offset`) is set, the whole computation is already in shared-window mode (rule 2), and `before_end_episode_offset`'s value gets used as a plain point instead of forming its own region. Which side "wins" when the two pairs disagree is entirely about whether an outer side is set *anywhere* on a non-full pair, not about which pair.

The last two rows are the case worth internalizing for full pairs: a full pair (both sides set) *always* keeps its own region, and never absorbs or suppresses whatever the other pair independently contributes — even when that other pair only has one side set. A full pair and a non-full, non-empty pair together always produce two regions, never one.

If a selected episode's engine call produces two regions (rule 1, or two pairs each independently "inner-only" under rule 3) or a constructor selects several episodes (e.g. `IN_PRIOR_PREG` with two prior episodes), each region/episode becomes its own candidate [Window](Window.md) row. See "Multiple candidate windows" in the tutorial for how the [Selector](Selector.md) then treats them.

## Step 3: capping a window to its own episode's real bounds (optional)

The border-offset formula in Step 2 has no idea how long a selected episode actually is — `after_start_episode_offset = 140` always adds 140 days to `start_episode`, even if that particular episode's `end_episode` is only 90 days later. Two optional logical metadata columns, both `NA`/unset by default (no effect), close that gap:

- `cap_start_to_episode = TRUE`: raises `window_start` up to at least the selected episode's own `start_episode` (`window_start := pmax(window_start, start_episode)`).
- `cap_end_to_episode = TRUE`: lowers `window_end` down to at most the selected episode's own `end_episode` (`window_end := pmin(window_end, end_episode)`).

Both are applied per selected episode, right after Step 2 builds that episode's window(s) and before Step 4's anchor clip runs. Neither errors; a window capped down past its other edge just comes out invalid like any other empty window. Not read by `OUTSIDE_ALL_PREG` (there's no single selected episode for it to cap against).

Worked example: episode `[2025-01-01, 2025-04-01]` (90 days long), `before_start_episode_offset = 0, after_start_episode_offset = 140` (a full start pair, its own region `[2025-01-01, 2025-05-21]`, 50 days past the episode's real end):

| `cap_end_to_episode` | result |
| --- | --- |
| `NA` (default) | `[2025-01-01, 2025-05-21]` — unaffected, exactly what Step 2 produced |
| `TRUE` | `[2025-01-01, 2025-04-01]` — end pulled back to the episode's real end |

## Step 4: clipping to the hard anchor-relative boundary (all four constructors)

Independently of steps 1–2, `anchor_start_offset`/`anchor_end_offset` define a hard boundary, `[anchor_start_col + anchor_start_offset, anchor_end_col + anchor_end_offset]`, that **every** candidate window from **every** episode-based constructor must fall inside — not just `IN_CURRENT_PREG`/`IN_PRIOR_PREG`/`IN_CURRENT_AND_PRIOR`'s windows, but `OUTSIDE_ALL_PREG`'s gaps too. `clip_to_anchor_bounds()` applies each side independently, and only when it's not `NA` (the same convention the border-offset pairs use):

- a set `anchor_start_offset` raises `window_start` up to at least the boundary's lower edge (`window_start := pmax(window_start, anchor_start_col + anchor_start_offset)`);
- a set `anchor_end_offset` lowers `window_end` down to at most the boundary's upper edge (`window_end := pmin(window_end, anchor_end_col + anchor_end_offset)`);
- leaving either `NA` (the default) means that side of the boundary isn't enforced at all.

A window entirely outside the boundary comes out with `window_start > window_end`, which `finalize_windows()` marks invalid the same way any other empty window is — this step never errors and never drops a row itself, it only narrows a window's bounds.

For `OUTSIDE_ALL_PREG` this step is a no-op: its search range for `outside_all_episode_gaps()` is already exactly `[anchor_start_col + anchor_start_offset, anchor_end_col + anchor_end_offset]`, so every gap it returns already satisfies the boundary by construction. For the other three constructors, this is what makes `anchor_start_offset`/`anchor_end_offset` behave as a project-wide hard time boundary — e.g. "no episode-based window may extend outside `[T0 - 1, T0 + 1]`" — applied uniformly regardless of which episode(s) the border-offset formula selected or how it shaped their windows.

## `OUTSIDE_ALL_PREG`: a different job for steps 1–2

`OUTSIDE_ALL` doesn't select or window individual episodes — it finds the gaps *between all* of a person's episodes inside `[anchor_start_col + anchor_start_offset, anchor_end_col + anchor_end_offset]`, and returns each gap as its own candidate window. The four border offsets from step 2 are not read at all for this constructor. An episode always fences the gaps around it, even the one containing the anchor itself, so there is no gap starting exactly at the anchor if the anchor falls inside an ongoing episode. See [OUTSIDE_ALL_PREG](OUTSIDE_ALL_PREG.md) for the search-range mechanics.
