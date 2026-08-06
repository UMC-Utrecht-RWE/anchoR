A single numerical example run through all four [episode-based](<../definitions/Episode-Based Window Engine.md>) constructors using the exported `define_window()` interface. Every table below was produced by actually running the snippet above it, not hand-computed.

## Setup

One person with three episodes and an anchor (`T0`) inside the third:

| Episode     | start_episode | end_episode |
| ----------- | ------------- | ----------- |
| A (prior)   | 2023-01-01    | 2023-09-01  |
| B (prior)   | 2024-03-01    | 2024-11-15  |
| C (current) | 2025-11-01    | 2026-08-01  |

`T0 = 2026-02-15` (falls inside episode C).

```r
library(anchoR)
library(data.table)

episodes <- data.table(
  person_id = "1",
  start_episode = as.Date(c("2023-01-01", "2024-03-01", "2025-11-01")),
  end_episode   = as.Date(c("2023-09-01", "2024-11-15", "2026-08-01"))
)
population <- data.table(person_id = "1", T0 = as.Date("2026-02-15"))

make_windows <- function(
  constructor,
  anchor_start_offset = NA_real_, anchor_end_offset = NA_real_,
  before_start_episode_offset = NA_real_, after_start_episode_offset = NA_real_,
  before_end_episode_offset = NA_real_, after_end_episode_offset = NA_real_
) {
  metadata <- data.table(
    variable_id = "demo",
    concept_id = "DEMO",
    constructor = constructor,
    selector = "ALL",
    start_offset = 0L,  # unused by episode-based constructors, still required
    end_offset = 0L,
    anchor_start_offset = anchor_start_offset,
    anchor_end_offset = anchor_end_offset,
    before_start_episode_offset = before_start_episode_offset,
    after_start_episode_offset = after_start_episode_offset,
    before_end_episode_offset = before_end_episode_offset,
    after_end_episode_offset = after_end_episode_offset
  )
  define_window(population, metadata, episodes = episodes)[
    window_valid == TRUE,
    .(window_start, window_end)
  ]
}
```

## [in_current_pregnancy](../definitions/IN_CURRENT_PREG.md)

With no border offsets set, episode C's own unshifted span becomes the window:

```r
make_windows("in_current_pregnancy")
```

| window_start | window_end |
| ------------ | ---------- |
| 2025-11-01   | 2026-08-01 |

Extending 14 days past the episode's own end (`after_end_episode_offset = 14`, the end pair's only side set):

```r
make_windows("in_current_pregnancy", after_end_episode_offset = 14)
```

| window_start | window_end |
| ------------ | ---------- |
| 2025-11-01   | 2026-08-15 |

## [in_prior_pregnancy](../definitions/IN_PRIOR_PREG.md)

With no border offsets set, both A and B (classified "prior" relative to current episode C) produce a window each, their own unshifted spans:

```r
make_windows("in_prior_pregnancy")
```

| window_start | window_end |
| ------------ | ---------- |
| 2023-01-01   | 2023-09-01 |
| 2024-03-01   | 2024-11-15 |

### `in_prior_pregnancy`, restricted to the first 90 days of each prior episode

Setting *both* sides of the start pair (`before_start_episode_offset = 0, after_start_episode_offset = 90`) turns it into its own self-contained region, `[start_episode, start_episode + 90]`; the end pair is left unset, so per the "exactly one pair fully specified" rule it contributes nothing:

```r
make_windows(
  "in_prior_pregnancy",
  before_start_episode_offset = 0, after_start_episode_offset = 90
)
```

| window_start | window_end | note                     |
| ------------ | ---------- | ------------------------ |
| 2023-01-01   | 2023-04-01 | episode A, first 90 days |
| 2024-03-01   | 2024-05-30 | episode B, first 90 days |

Compare to the unrestricted row above: both episodes' full spans (through `2023-09-01`/`2024-11-15`) are gone entirely, not clipped a fully-specified pair replaces the shared window, it doesn't shrink it.

## [in_current_and_prior](../definitions/IN_CURRENT_AND_PRIOR.md)

The union of the two constructors above, same (unset) border offsets:

```r
make_windows("in_current_and_prior")
```

| window_start | window_end | which episode |
| ------------ | ---------- | ------------- |
| 2025-11-01   | 2026-08-01 | C (current)   |
| 2023-01-01   | 2023-09-01 | A (prior)     |
| 2024-03-01   | 2024-11-15 | B (prior)     |

## The hard anchor-relative boundary

`anchor_start_offset`/`anchor_end_offset` clip *every* constructor's window to `[T0 + anchor_start_offset, T0 + anchor_end_offset]`, not just `outside_all_pregnancy`'s search range. Applied to `in_current_pregnancy` with no border offsets (episode C's unshifted span, `[2025-11-01, 2026-08-01]`) and `anchor_start_offset = -30, anchor_end_offset = 0`:

```r
make_windows("in_current_pregnancy", anchor_start_offset = -30, anchor_end_offset = 0)
```

| window_start | window_end | note                                             |
| ------------ | ---------- | ------------------------------------------------- |
| 2026-01-16   | 2026-02-15 | episode C's span, clipped to the 30 days before T0 |

## [outside_all_pregnancy](../definitions/OUTSIDE_ALL_PREG.md)

`anchor_start_offset = -1172, anchor_end_offset = 0`: search range `[2022-12-01, 2026-02-15]`. Three gaps come back, fenced by A, B, and C; none touches `T0` since it sits inside the still-ongoing episode C. This constructor doesn't read the four border-offset columns at all only `anchor_start_offset`/`anchor_end_offset` matter, and they define the search range itself:

```r
make_windows("outside_all_pregnancy", anchor_start_offset = -1172L, anchor_end_offset = 0L)
```

| window_start | window_end | gap             |
| ------------ | ---------- | --------------- |
| 2022-12-01   | 2022-12-31 | before A        |
| 2023-09-02   | 2024-02-29 | between A and B |
| 2024-11-16   | 2025-10-31 | between B and C |
