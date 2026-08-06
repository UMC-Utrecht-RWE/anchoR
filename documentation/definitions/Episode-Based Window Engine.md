> `pregnancy_window_engine()`: the shared implementation behind all four episode-based [constructors](Constructor.md). This page is the **canonical** description of how it turns a person's episodes into windows — the four constructor pages ([IN_CURRENT_PREG](IN_CURRENT_PREG.md), [IN_PRIOR_PREG](IN_PRIOR_PREG.md), [IN_CURRENT_AND_PRIOR](IN_CURRENT_AND_PRIOR.md), [OUTSIDE_ALL_PREG](OUTSIDE_ALL_PREG.md)) and the [episode-window tutorial](../Tutorial_pregnancy_windows.md)/vignette only say what's specific to each one and link back here for the formula itself.

Every episode-based constructor is this one engine, pre-configured with an `episode_select` (`"CURRENT"`, `"PRIOR"`, `"CURRENT_AND_PRIOR"`, or `"OUTSIDE_ALL"`). Adding a new named shape later means adding a short wrapper around this engine, not a new bespoke implementation.

Episodes come from the [Episodes](Episodes.md) input table, nested onto [Population](Population.md) internally (one small `data.table(start_episode, end_episode)` per person, in a `.episodes` list-column) before any constructor runs; a caller only ever deals with the flat `episodes` table.

There are three independent steps: **which episode(s) are selected**, **where each selected episode's window(s) sit**, and **clipping every resulting window to a hard anchor-relative boundary**.

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

Each side is read as `edge + offset` (`0` means "exactly on the edge"; `NA` means "this side isn't set"). The rule, in order:

1. **A pair with both sides set** is always its own self-contained region, `[edge + before_offset, edge + after_offset]`, regardless of what the other pair does. `before_offset` must not be later than `after_offset`, or that region would be inverted, which is an error.
2. Otherwise, if **either pair's outer side is set alone** (`before_start_episode_offset` alone, or `after_end_episode_offset` alone), the *whole computation* becomes **one shared window**: that side's offset defines its edge directly (`start_episode + before_start_episode_offset`, or `end_episode + after_end_episode_offset`); the *other* pair contributes whichever single value it has — regardless of which side it is — as a plain point for the opposite edge, or the unshifted edge if that other pair has nothing set at all. This is the only way one pair's value and the other pair's value combine into a single window.
3. Otherwise (no outer side set anywhere, so any pair with content only has its **inner** side set), each such pair forms its **own region** instead, missing side defaulting to `0`; a pair with nothing set contributes nothing.
4. If **neither pair has anything set**, the result is one shared window: the episode's own unshifted span, `[start_episode, end_episode]`.

Worked examples, episode `[2025-01-07, 2025-05-07]`:

| `before_start` | `after_start` | `before_end` | `after_end` | rule | result |
| --------------- | -------------- | ------------- | ------------- | ---- | ------ |
| `NA` | `NA` | `NA` | `NA` | (4) neither set | one window, `[2025-01-07, 2025-05-07]` |
| `0` | `NA` | `NA` | `0` | (2) both outer sides set alone | one shared window, `[2025-01-07, 2025-05-07]` (each edge pinned) |
| `-31` | `NA` | `NA` | `31` | (2) both outer | one shared window, `[2024-12-07, 2025-06-07]` |
| `NA` | `0` | `0` | `NA` | (3) both inner, no outer anywhere | two single-day regions, `[2025-01-07, 2025-01-07]` and `[2025-05-07, 2025-05-07]` |
| `NA` | `31` | `-31` | `NA` | (3) both inner | two regions, `[2025-01-07, 2025-02-07]` and `[2025-04-06, 2025-05-07]` |
| `-7` | `NA` | `-7` | `NA` | (2) start's outer side set alone; end's only side is its *inner* one, but outer-mode is already active, so it's used as a plain point anyway | one shared window, `[2024-12-31, 2025-04-30]` |
| `NA` | `50` | `NA` | `NA` | (3) start's inner side alone, end pair fully empty | one region, `[2025-01-07, 2025-02-26]`; end contributes nothing |
| `-7` | `7` | `-7` | `7` | (1) both pairs fully specified | two regions: `[2024-12-31, 2025-01-14]` and `[2025-04-30, 2025-05-14]` |

The fifth row (`-7`/`NA`/`-7`/`NA`) is the case worth internalizing: `before_end_episode_offset` is normally "inner" (rule 3, own region) — but because the *start* pair's outer side (`before_start_episode_offset`) is set, the whole computation is already in shared-window mode (rule 2), and `before_end_episode_offset`'s value gets used as a plain point instead of forming its own region. Which side "wins" when the two pairs disagree is entirely about whether an outer side is set *anywhere*, not about which pair.

If a selected episode's engine call produces two regions (rule 1, or two pairs each independently "inner-only" under rule 3) or a constructor selects several episodes (e.g. `IN_PRIOR_PREG` with two prior episodes), each region/episode becomes its own candidate [Window](Window.md) row. See "Multiple candidate windows" in the tutorial for how the [Selector](Selector.md) then treats them.

## Step 3: clipping to the hard anchor-relative boundary (all four constructors)

Independently of steps 1–2, `anchor_start_offset`/`anchor_end_offset` define a hard boundary, `[anchor_start_col + anchor_start_offset, anchor_end_col + anchor_end_offset]`, that **every** candidate window from **every** episode-based constructor must fall inside — not just `IN_CURRENT_PREG`/`IN_PRIOR_PREG`/`IN_CURRENT_AND_PRIOR`'s windows, but `OUTSIDE_ALL_PREG`'s gaps too. `clip_to_anchor_bounds()` applies each side independently, and only when it's not `NA` (the same convention the border-offset pairs use):

- a set `anchor_start_offset` raises `window_start` up to at least the boundary's lower edge (`window_start := pmax(window_start, anchor_start_col + anchor_start_offset)`);
- a set `anchor_end_offset` lowers `window_end` down to at most the boundary's upper edge (`window_end := pmin(window_end, anchor_end_col + anchor_end_offset)`);
- leaving either `NA` (the default) means that side of the boundary isn't enforced at all.

A window entirely outside the boundary comes out with `window_start > window_end`, which `finalize_windows()` marks invalid the same way any other empty window is — this step never errors and never drops a row itself, it only narrows a window's bounds.

For `OUTSIDE_ALL_PREG` this step is a no-op: its search range for `outside_all_episode_gaps()` is already exactly `[anchor_start_col + anchor_start_offset, anchor_end_col + anchor_end_offset]`, so every gap it returns already satisfies the boundary by construction. For the other three constructors, this is what makes `anchor_start_offset`/`anchor_end_offset` behave as a project-wide hard time boundary — e.g. "no episode-based window may extend outside `[T0 - 1, T0 + 1]`" — applied uniformly regardless of which episode(s) the border-offset formula selected or how it shaped their windows.

## `OUTSIDE_ALL_PREG`: a different job for steps 1–2

`OUTSIDE_ALL` doesn't select or window individual episodes — it finds the gaps *between all* of a person's episodes inside `[anchor_start_col + anchor_start_offset, anchor_end_col + anchor_end_offset]`, and returns each gap as its own candidate window. The four border offsets from step 2 are not read at all for this constructor. An episode always fences the gaps around it, even the one containing the anchor itself, so there is no gap starting exactly at the anchor if the anchor falls inside an ongoing episode. See [OUTSIDE_ALL_PREG](OUTSIDE_ALL_PREG.md) for the search-range mechanics.
