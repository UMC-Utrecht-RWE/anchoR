# Recipes: pregnancy windows from protocol to metadata

This page is for people who know which window the study protocol wants ("the year before LMP", "first trimester") and need the metadata row that produces it. Find your phrase in the index, copy the row, and read the gotchas. You don't need to understand how the episode engine works to use it.

If no recipe fits, [Tutorial_pregnancy_windows.md](Tutorial_pregnancy_windows.md) explains the building blocks and [Episode-Based Window Engine](<definitions/Episode-Based Window Engine.md>) has the full rules.

## How to read a recipe

Every recipe uses the same example person, so you can compare them directly:

```
             earlier pregnancy                current pregnancy
         [2025-03-01 ── 2025-06-15]       [2025-12-01 ─────────────── 2026-09-01]
                                           LMP              T0
                                           2025-12-01       2026-06-15 (28 weeks)
```

```r
episodes <- data.table(
  person_id     = "1",
  start_episode = as.Date(c("2025-03-01", "2025-12-01")),  # start_episode = LMP
  end_episode   = as.Date(c("2025-06-15", "2026-09-01"))
)
population <- data.table(
  person_id = "1",
  T0        = as.Date("2026-06-15"),
  lmp_date  = as.Date("2025-12-01")  # only needed by recipes 6b and 5b
)
```

Each recipe lists **only the columns you need to set**. Leave every other column `NA`, including `start_offset`/`end_offset`, which episode-based constructors never read (see [which columns each constructor reads](Input_metadata.md#which-columns-each-constructor-reads)). A full row looks like this:

```r
metadata <- data.table(
  variable_id  = "my_variable",
  concept_id   = "MY_CONCEPT",
  selector     = "LATEST",
  start_offset = NA_integer_,
  end_offset   = NA_integer_,
  # ... plus the columns from the recipe
  constructor  = "in_current_pregnancy",
  after_start_episode_offset = 83
)
```

Every "Result" below is the real `define_window()` output for the example person.

Day arithmetic is inclusive on both ends: `LMP + 83` is the 84th day of pregnancy, the last day of week 12.

## Index

| The protocol says…                                           | Recipe                                                                     |
| ------------------------------------------------------------ | -------------------------------------------------------------------------- |
| any time during the current pregnancy                        | [1](#1-any-time-during-the-current-pregnancy)                              |
| from LMP up to T0 (or the day before)                        | [2](#2-from-lmp-up-to-t0)                                                  |
| first trimester / first N weeks of pregnancy                 | [3](#3-first-trimester--first-n-weeks)                                     |
| N days before LMP                                            | [4](#4-n-days-before-lmp)                                                  |
| N days before LMP through the first trimester                | [5](#5-n-days-before-lmp-through-the-first-trimester)                      |
| before pregnancy, excluding earlier pregnancies              | [6](#6-before-pregnancy-excluding-earlier-pregnancies)                     |
| during any earlier pregnancy                                 | [7](#7-during-any-earlier-pregnancy)                                       |
| N days after delivery                                        | [8](#8-n-days-after-delivery)                                              |
| from N days before LMP up to T0                              | [9](#9-from-n-days-before-lmp-up-to-t0)                                    |
| during the current or any earlier pregnancy                  | [10](#10-during-the-current-or-any-earlier-pregnancy)                      |
| two of the above combined into one variable                  | [Combining windows](#combining-two-windows-into-one-variable)              |

---

### 1. Any time during the current pregnancy

| column        | value                  |
| ------------- | ---------------------- |
| `constructor` | `in_current_pregnancy` |

**Result:** `[2025-12-01, 2026-09-01]`, i.e. `[LMP, end of pregnancy]`.

**Gotchas**
- The window runs to the **end** of the pregnancy, past T0. For a covariate that must be known at T0, use recipe 2 instead.
- A person whose T0 is not inside a pregnancy gets no window and no result.

### 2. From LMP up to T0

| column              | value                                   |
| ------------------- | --------------------------------------- |
| `constructor`       | `in_current_pregnancy`                  |
| `anchor_end_offset` | `0` (up to T0) or `-1` (day before T0)  |

**Result** (with `-1`): `[2025-12-01, 2026-06-14]`, i.e. `[LMP, T0 − 1]`.

**Gotchas**
- `anchor_end_offset` doesn't move the window; it cuts it off. The window is still the whole pregnancy, clipped at `T0 + anchor_end_offset`.
- With `-1`, a person whose T0 is the first day of pregnancy gets an empty window and no result.

### 3. First trimester / first N weeks

| column                       | value                  |
| ---------------------------- | ---------------------- |
| `constructor`                | `in_current_pregnancy` |
| `after_start_episode_offset` | `83` (12 weeks)        |
| `cap_end_to_episode`         | `TRUE`                 |

**Result:** `[2025-12-01, 2026-02-22]`, i.e. `[LMP, LMP + 83]`.

**Gotchas**
- **Check your protocol's definition of the first trimester.** 12 weeks is `83`; up to 13 weeks + 6 days is `97`. For "the first N weeks", use `N × 7 − 1`.
- `cap_end_to_episode = TRUE` stops the window at the end of a pregnancy shorter than 12 weeks. Without it, a pregnancy from `2025-12-01` to `2026-02-09` would get `[2025-12-01, 2026-02-22]`, picking up records from after the pregnancy ended. With it, the window is `[2025-12-01, 2026-02-09]`.
- If T0 is before the end of week 12, the window reaches past T0. Add `anchor_end_offset = 0` (recipe 2) if that matters.

### 4. N days before LMP

| column                        | value                  |
| ----------------------------- | ---------------------- |
| `constructor`                 | `in_current_pregnancy` |
| `before_start_episode_offset` | `-365`                 |
| `after_start_episode_offset`  | `-1`                   |

**Result:** `[2024-12-01, 2025-11-30]`, i.e. `[LMP − 365, LMP − 1]`.

**Gotchas**
- **Both columns must be set.** With only `before_start_episode_offset = -365`, the window runs from `LMP − 365` to the **end of the current pregnancy** (`[2024-12-01, 2026-09-01]`). Setting both sides of the start pair is what makes it a self-contained "before LMP" window.
- This window **includes** earlier pregnancies (here, all of `2025-03-01` to `2025-06-15`). To exclude them, see recipe 6.
- The episode is found through T0, so the person's T0 must be inside the current pregnancy.

### 5. N days before LMP through the first trimester

| column                        | value                  |
| ----------------------------- | ---------------------- |
| `constructor`                 | `in_current_pregnancy` |
| `before_start_episode_offset` | `-365`                 |
| `after_start_episode_offset`  | `83`                   |
| `cap_end_to_episode`          | `TRUE`                 |

**Result:** `[2024-12-01, 2026-02-22]`, i.e. `[LMP − 365, LMP + 83]`.

**Gotchas**
- Like recipe 4, this includes earlier pregnancies. To exclude them, combine recipe 6b with recipe 3 (see [Combining windows](#combining-two-windows-into-one-variable)).
- `cap_end_to_episode` works as in recipe 3.

**5b. Without the episodes table.** If `population` has an LMP column, `GENERIC` gives the same window:

| column                                | value      |
| ------------------------------------- | ---------- |
| `constructor`                         | `GENERIC`  |
| `anchor_start_col`, `anchor_end_col`  | `lmp_date` |
| `start_offset`                        | `-365`     |
| `end_offset`                          | `83`       |

**Result:** `[2024-12-01, 2026-02-22]`. This version doesn't need T0 to be inside the pregnancy, but it has no `cap_end_to_episode`: a short pregnancy still gets the full 84 days.

### 6. Before pregnancy, excluding earlier pregnancies

`outside_all_pregnancy` returns the parts of a range that are **not inside any pregnancy**. It never includes a day inside a pregnancy, the current one included. What matters is which date the range is measured from.

**6a. Measured from T0** (the default):

| column                | value                   |
| --------------------- | ----------------------- |
| `constructor`         | `outside_all_pregnancy` |
| `anchor_start_offset` | `-365`                  |
| `anchor_end_offset`   | `-1`                    |

**Result:** `[2025-06-16, 2025-11-30]`, only 168 days.

The range is `[T0 − 365, T0 − 1]`, but the current pregnancy removes everything from LMP onwards and the earlier pregnancy removes everything up to `2025-06-15`. **When T0 is mid-pregnancy, this is not "365 days before LMP"**, and the later T0 falls in pregnancy, the shorter the window gets.

**6b. Measured from LMP** (usually what the protocol means):

| column                               | value                   |
| ------------------------------------ | ----------------------- |
| `constructor`                        | `outside_all_pregnancy` |
| `anchor_start_col`, `anchor_end_col` | `lmp_date`              |
| `anchor_start_offset`                | `-365`                  |
| `anchor_end_offset`                  | `-1`                    |

**Result:** two windows, `[2024-12-01, 2025-02-28]` and `[2025-06-16, 2025-11-30]`: the year before LMP with the earlier pregnancy cut out. The selector looks across both.

**Gotchas**
- 6b needs an LMP column in `population` (the current pregnancy's LMP for each row).
- Check that your pipeline doesn't overwrite `anchor_start_col`/`anchor_end_col` with `T0` before calling `anchor()`; if it does, 6b silently becomes 6a.
- Neither version can reach into the current pregnancy. For "before LMP through the first trimester, excluding earlier pregnancies", combine 6b with recipe 3.

### 7. During any earlier pregnancy

| column        | value                |
| ------------- | -------------------- |
| `constructor` | `in_prior_pregnancy` |

**Result:** `[2025-03-01, 2025-06-15]`. A person with three earlier pregnancies gets three windows.

**Gotchas**
- There's no built-in "most recent earlier pregnancy only". `LATEST` returns the latest record across **all** earlier pregnancies, which is not the same thing.
- "Earlier" means ended before the current pregnancy started. A person whose T0 is not in a pregnancy still gets every pregnancy that ended before T0.
- Add `anchor_start_offset` (e.g. `-1825`) to only look at earlier pregnancies within the last N days of T0.

### 8. N days after delivery

| column                      | value                  |
| --------------------------- | ---------------------- |
| `constructor`               | `in_current_pregnancy` |
| `before_end_episode_offset` | `1`                    |
| `after_end_episode_offset`  | `42`                   |

**Result:** `[2026-09-02, 2026-10-13]`, i.e. `[end + 1, end + 42]`.

**Gotchas**
- **Both columns must be set.** With only `after_end_episode_offset = 42`, the window runs from **LMP** to `end + 42` (`[2025-12-01, 2026-10-13]`): the whole pregnancy plus 42 days.
- Use `0` instead of `1` to include the delivery date itself.
- This window is after T0, so it suits outcomes and follow-up, not covariates. For "after the end of earlier pregnancies", use the same columns with `in_prior_pregnancy`.

### 9. From N days before LMP up to T0

| column                        | value                  |
| ----------------------------- | ---------------------- |
| `constructor`                 | `in_current_pregnancy` |
| `before_start_episode_offset` | `-365`                 |
| `anchor_end_offset`           | `0`                    |

**Result:** `[2024-12-01, 2026-06-15]`, i.e. `[LMP − 365, T0]`.

**Gotchas**
- Here `before_start_episode_offset` is set **alone** on purpose: that makes the window run to the end of the pregnancy (see recipe 4's first gotcha), and `anchor_end_offset = 0` then cuts it at T0.
- Includes earlier pregnancies, like recipe 4.

### 10. During the current or any earlier pregnancy

| column        | value                  |
| ------------- | ---------------------- |
| `constructor` | `in_current_and_prior` |

**Result:** two windows, `[2025-12-01, 2026-09-01]` and `[2025-03-01, 2025-06-15]`.

**Gotchas**
- Every pregnancy gets the same offsets. If the current and earlier pregnancies need different windows, write recipe 1 and recipe 7 as two rows and [combine them](#combining-two-windows-into-one-variable).
- Like recipe 1, the current pregnancy's window runs past T0 unless you add `anchor_end_offset`.

---

## Combining two windows into one variable

Write two rows with the **same `variable_id` and the same `window_name`** (both `NA` is fine). The rows can use different constructors. anchoR treats them as one variable with several windows, and the selector picks across all of them.

Example: "obesity in the year before LMP, excluding earlier pregnancies, or in the first 12 weeks" is recipe 6b plus recipe 3:

| `variable_id` | `constructor`           | `anchor_start_col`/`anchor_end_col` | `anchor_start_offset` | `anchor_end_offset` | `after_start_episode_offset` | `cap_end_to_episode` |
| ------------- | ----------------------- | ----------------------------------- | --------------------- | ------------------- | ---------------------------- | -------------------- |
| `obesity`     | `outside_all_pregnancy` | `lmp_date`                          | `-365`                | `-1`                | `NA`                         | `NA`                 |
| `obesity`     | `in_current_pregnancy`  | `T0`                                | `NA`                  | `NA`                | `83`                         | `TRUE`               |

For the example person with records on `2025-01-10`, `2025-04-01`, `2026-01-20` and `2026-05-01`, `selector = "ALL"` returns `2025-01-10` (before LMP, outside the earlier pregnancy) and `2026-01-20` (first trimester). `2025-04-01` is inside the earlier pregnancy and `2026-05-01` is after week 12, so both are excluded. `LATEST` returns `2026-01-20`.

**Gotchas**
- If the windows **overlap**, a record in the overlap is matched twice, which inflates `COUNT`. Make the windows touch, not overlap (here one ends at `LMP − 1` and the other starts at LMP).
- Rows with **different** `window_name`s are *not* combined: each produces its own result.

## Things one row can't express

| You want…                                              | Do this instead                                                                               |
| ------------------------------------------------------ | --------------------------------------------------------------------------------------------- |
| only the most recent earlier pregnancy                 | no built-in; derive it upstream (e.g. add it as its own episodes table)                       |
| different offsets for the current and earlier pregnancies | two rows, [combined](#combining-two-windows-into-one-variable)                             |
| a window measured from LMP when T0 is not in pregnancy | `GENERIC` anchored on an LMP column (recipe 5b)                                              |
| "before LMP, excluding earlier pregnancies" with no LMP column in `population` | add the column; `outside_all_pregnancy` measured from T0 (6a) is a different window |

## Check your row before anchoring

Run your metadata through `define_window()` for a handful of people and look at the dates. It takes seconds and catches most mistakes:

```r
windows <- define_window(population, metadata, episodes = episodes)
windows[, .(person_id, T0, variable_id, constructor, window_start, window_end, window_valid)]
```

Things to look for:
- **No row for a person**: the constructor found no pregnancy (e.g. T0 not inside one, for `in_current_pregnancy`).
- **`window_valid = FALSE`**: the window ends before it starts, usually because an anchor clip cut it away entirely.
- **A window much shorter or longer than the protocol says**: compare against the recipe's gotchas, especially recipe 4 (one column instead of two) and recipe 6 (measured from T0 instead of LMP).
