# Quickstart (no epidemiology or R jargon required)

If you're brand new to this package, start here. Everything below assumes nothing except that you can run R code.

## What problem does this solve?

Imagine you have a spreadsheet of patients, and for each one you want to answer questions like:

- "Did they get a flu vaccine in the year before their visit?"
- "How many times were they hospitalized in the 90 days before surgery?"

The tricky part isn't the question, it's that **the time window is different for every person** (person A's "year before their visit" is a totally different calendar range than person B's), and you might have thousands of people and dozens of questions. Doing this by hand, or with a pile of copy-pasted code, is slow and easy to get wrong.

anchoR does this for you: you describe your people, your questions, and your raw event data, and it works out the right window for everyone and gives you back the answers.

## The five words you need to know

| word                   | plain-English meaning                                                                                                                                                                                                  |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **T0** ("anchor date") | The date everything is measured relative to for one person e.g. their visit date, their enrollment date. Short for "time zero."                                                                                        |
| **window**             | The date range built around T0 for one question e.g. "365 days before T0, through T0."                                                                                                                                 |
| **concept**            | One recorded fact about a person on a date a diagnosis, a lab value, a vaccination. Your raw data.                                                                                                                     |
| **selector**           | How to boil down whatever concepts fall inside a window into one answer "give me the most recent one," "count them," "just tell me yes/no."                                                                            |
| **constructor**        | The rule that decides *where* a window sits. Almost always "a fixed number of days around T0" there's a fancier option for things that can happen more than once, like pregnancy, covered separately once you need it. |

That's the whole vocabulary. Everything else in the docs is a variation on these five ideas.

## The three tables you provide

1. **`population`** one row per person, with their T0 date.
2. **`metadata`** one row per question you want answered (what to look for, how far back/forward to look, how to reduce it to one answer).
3. **`concepts`** your raw event data: one row per person, per recorded fact, per date.

## A complete, runnable example

```r
library(anchoR)
library(data.table)

# Step 1: who are we asking about, and what's their T0?
population <- data.table(
  person_id = c("1", "2"),
  T0        = as.Date(c("2024-01-01", "2024-01-01"))
)

# Step 2: what do we want to know?
# "Was there a flu vaccine in the 365 days up to and including T0?
#  If there's more than one, give me the most recent."
metadata <- data.table(
  variable_id  = "flu_vaccine_recent",
  concept_id   = "FLU_VAX",
  constructor  = "GENERIC",   # a fixed window around T0
  selector     = "LATEST",    # the most recent matching record
  start_offset = -365L,       # 365 days before T0 ...
  end_offset   = 0L           # ... through T0 itself
)

# Step 3: the raw data to search through.
concepts <- data.table(
  person_id  = "1",
  concept_id = "FLU_VAX",
  date       = as.Date("2023-10-01"),
  value      = "TRUE"
)

# Run it. Results are written to a folder ("hive_path"), not returned directly.
hive_path <- tempfile(pattern = "anchor-hive-")
dir.create(hive_path)

anchor(population, metadata, concepts, anchor_hive_path = hive_path)

# Read the results back.
get_anchor_result(metadata, hive_path, result_shape = "long")
#>    person_id         T0        variable_id window_name       date value
#> 1:         1 2024-01-01 flu_vaccine_recent        <NA> 2023-10-01  TRUE
```

Walking through what just happened: person 1's window was `[2023-01-02, 2024-01-01]` (365 days before T0, through T0). Their one `FLU_VAX` record, dated `2023-10-01`, falls inside it, so it comes back as the answer. Person 2 has no matching record at all they simply don't appear in the output. That's normal: **results are sparse by default**, a missing row means "no match," not an error.

## What to read next

- Want a wide table (one row per person, one column per question) instead of one row per match? See [Tutorial_standard_windows.md](Tutorial_standard_windows.md) the "Multiple windows for the same variable" and `get_anchor_result(..., result_shape = "wide")` sections.
- Have a question that isn't tied to one fixed date e.g. anything about pregnancy, or another event that can happen more than once? See [Tutorial_pregnancy_windows.md](Tutorial_pregnancy_windows.md).
- Want to see every built-in `selector` (`LATEST`, `EARLIEST`, `COUNT`, ...) and what each returns? See `vignette("selector-cookbook", package = "anchoR")`.
- Not sure where to go from here at all? [documentation/README.md](README.md) routes you by task.
