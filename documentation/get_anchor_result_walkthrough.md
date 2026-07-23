# `get_anchor_result()`: a block-by-block walkthrough

This document explains `R/get_anchor_result.R` block by block: what each piece does, and, more importantly, *why* it's written the way it is. Line numbers refer to the file as of this writing.

## The big picture

`get_anchor_result()` answers one question: *"Give me the values of these variables, at these anchor dates, for these people, in a shape I can analyse."*

It has three ingredients:

- **`metadata`**: which variables to fetch (and optionally, which time windows).
- **`anchor_hive_path`**: a directory of parquet files (a "hive") holding already-computed anchored variables, one partition per variable/window.
- **`population`** *(optional)*: which `person_id`/`T0` pairs you actually care about, plus any extra columns you want carried through to the output.

The function reads the parquet hive with DuckDB, filters it down to the requested variables, and reshapes it into either a sparse `long` table or a `wide` table keyed by person/date/window (or person/date when `cast_window = TRUE`).
The `population` argument is optional plumbing layered on top of that core job.

---

## `population_conflict_columns()` (lines 1–19)

```r
population_conflict_columns <- function(
  population_dt, duplicate_keys, required_columns
) { ... }
```

**What:** Given a table and a set of keys known to be duplicated, this
returns the names of the *other* columns whose values actually differ across
those duplicate rows.

It works by re-selecting just the duplicated rows (`conflicting_rows`), then
for each key group, counting how many distinct values (`uniqueN`) each other
column takes. If a column has more than one distinct value within a group, it
"varies" i.e., it's a genuine conflict, not just a coincidental repeat.

**Why it exists as a separate function:** The main function needs to warn the
caller *which* columns disagree (see below), not just that a duplicate
exists. Splitting this out keeps that "which columns diverge" logic testable
in isolation, and it has its own dedicated unit tests
(`test_get-anchor-result.R`), separate from the full `get_anchor_result()`
integration test.

---

## Function signature & docs (lines 21–68)

The roxygen block documents the contract. The two details worth internalizing
because they explain choices later in the function body:

- `population` is optional. Its presence toggles a lot of behavior (filtering
  to a population, deduplication, reattaching extra columns). Its absence
  means "just give me everything in the hive that matches the metadata."
- The docs already flag the duplicate-key behavior up front: *"When multiple
  rows share the same `person_id`/`T0` key but disagree on other columns
  (e.g. matching with replacement), the first row per key is kept, a warning
  names the conflicting column(s), and processing continues."* This is a
  deliberate design choice, not an oversight; see the dedup block below for
  why.

---

## DuckDB connection setup (lines 70–73)

```r
con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:", read_only = FALSE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
```

**What:** Opens an in-memory DuckDB connection and guarantees it's closed
when the function exits (success or error), via `on.exit`.

**Why DuckDB at all:** The comment above it is the key: *"Different selectors
may return slightly different columns, so the combined result needs a
forgiving row bind instead of assuming one rigid shape."* The anchor hive is
a directory of parquet files written independently by different variable
selectors, which may not all have identical columns. DuckDB's
`read_parquet(..., union_by_name = true)` (used later) does a
column-name-aware union across files, something that's fiddly to replicate
correctly by hand with pure R row-binding, especially at scale. Using SQL
here also means the heavy filtering happens inside DuckDB rather than after
pulling everything into R memory.

**Why `on.exit(..., add = TRUE)`:** so that if something later in the
function throws an error, the connection still gets cleaned up rather than
leaking.

---

## Normalizing `metadata` (lines 75–81)

```r
metadata_dt <- as_data_table(metadata, "metadata")
assert_has_columns(metadata_dt, required = "variable_id", arg = "metadata")
add_column_if_missing(metadata_dt, "window_name", NA_character_)
```

**What:** Coerces `metadata` to a `data.table` (copying it, so the caller's
original object isn't mutated by later in-place `data.table` operations),
asserts it has a `variable_id` column, and ensures a `window_name` column
exists (defaulting to `NA`) if the caller didn't supply one.

**Why:** `window_name` is optional from the caller's perspective; you might
just want "the latest value of X" with no window concept, but the rest of
the function's logic (the SQL join condition, the wide-cast formula) needs
the column to exist unconditionally so it doesn't have to branch on whether
it's present. Filling in `NA` here means "no specific window requested," which
the SQL below interprets as a wildcard.

---

## The `population` block (lines 83–133)

This is the most involved section, and the one most worth understanding in
detail. It only runs `if (!is.null(population))`; the function is fully
usable without a population filter.

### 1. Validate required columns (lines 87–101)

```r
population_dt <- as_data_table(population, "population")
missing_population_cols <- setdiff(required_population_cols, names(population_dt))
if (length(missing_population_cols) > 0L) { ... stop(...) }
```

**What/why:** Same defensive pattern as `metadata`: fail loudly and early
with a specific message if `person_id`/`T0` and any additional
`required_population_cols` aren't present, rather than failing
later with a cryptic error deep inside a join or a `dcast`.

### 2. Full-row dedup (line 103)

```r
population_dt <- unique(population_dt)
```

**Why:** If the caller accidentally passed in exact duplicate rows (same
`person_id`, `T0`, *and* every other column), those aren't a "conflict";
they're just redundant. Removing them here means the duplicate-key check
right after only reacts to *meaningful* disagreements, not noise. This also
means: if two rows share a key and survive past this line, they are
guaranteed to differ in at least one other column.

### 3. Detect duplicate keys and decide what to do about them (lines 104–127)

```r
duplicate_population_keys <- population_dt[, .N, by = .(person_id, T0)][N > 1L]
if (nrow(duplicate_population_keys) > 0L) {
  conflicting_cols <- population_conflict_columns(...)
  msg <- paste(...)
  logger::log_warn(msg)
  warning(msg, call. = FALSE)
  population_dt <- unique(population_dt, by = required_population_cols)
}
```

**What:** Counts rows per `person_id`/`T0` key. If any key has more than one
row, it:
1. Figures out which columns disagree (via `population_conflict_columns()`).
2. Logs and raises a `warning()` naming those columns.
3. Collapses to one row per key, keeping the first occurrence.

**Why a warning and not an error:** The comment says it directly: *"Matching
with replacement can legitimately assign the same control to multiple
exposed persons, so a repeated `person_id`/`T0` key is not an error."* In
epidemiological matched-cohort designs, the same control subject can be
matched to more than one case. That produces exactly this shape of data: same
`person_id`/`T0`, different `match_id` (or similar). Since this is an
expected, legitimate scenario rather than a data bug, hard-stopping the whole
pipeline would be the wrong default. A warning lets processing continue while
still surfacing the ambiguity to the caller.

**Why this still matters / the tradeoff:** The wide output format (built
later in the function) is keyed on `person_id` + `T0`; it has no way to
represent two rows for the same person on the same date. So *some*
collapsing is unavoidable if you want wide output. The function picks
"first row wins" as the resolution strategy. That's simple and
deterministic, but it means whichever column varies (e.g. `match_id`) gets
silently narrowed down to one value; see the note on the final reattachment
step below for where this actually bites.

### 4. Normalize `T0` and compute the population's keys (lines 129–132)

```r
population_dt[, T0 := as.Date(T0)]
population_keys_dt <- unique(population_dt[, .(person_id, T0)])
```

**What:** Coerces `T0` to `Date` (so later joins against the parquet-derived
`T0` compare like with like), and extracts just the unique key pairs into
`population_keys_dt`.

**Why keep a separate `population_keys_dt` instead of just using
`population_dt` everywhere:** The comment explains it: *"Wide output
cardinality is defined by the anchor key, but callers may need the rest of
the population columns carried into the final result."* These are two
different jobs: `population_keys_dt` (just the keys) is used to **filter and
shape** the output row-count; `population_dt` (keys + extra columns) is used
later only to **enrich** the final result with those extra columns. Keeping
them separate avoids the full population table's extra columns leaking into
row-count-determining joins earlier in the pipeline, where they don't belong.

---

## Validating and querying the anchor hive (lines 135–188)

```r
if (is.null(anchor_hive_path) || !dir.exists(anchor_hive_path)) { ... stop(...) }
...
DBI::dbExecute(con, "CREATE VIEW anchored_variables AS SELECT * FROM read_parquet(...)")
...
requested_results_dt <- unique(metadata_dt[, .(variable_id, window_name)])
...
DBI::dbWriteTable(con, name = "requested_results", value = requested_results_dt, ...)
anchored_dt <- ... dbGetQuery(con, "SELECT a.* FROM anchored_variables AS a WHERE EXISTS (...)")
```

**What:** Validates the hive path exists, registers it as a SQL view, writes
the caller's requested `(variable_id, window_name)` pairs as a small table,
and runs a `WHERE EXISTS` semi-join to pull only the rows from the hive that
match a requested variable (and window, if one was specified).

**Why do the filtering in SQL instead of in R after loading everything:**
Anchor hives can be large (that's the whole reason they're partitioned
parquet rather than one big CSV). Pushing the filter down to DuckDB means
only the relevant rows ever get materialized into R's `anchored_dt`.

**Why `r.window_name IS NULL OR a.window_name = r.window_name`:** This is the
"wildcard" behavior alluded to earlier: a `NA`/`NULL` `window_name` in the
requested metadata means "give me this variable regardless of window,"
rather than "give me the row where window is missing."

**Why coerce `date`/`T0` back after the round trip (lines 181–188):** The
comment explains: *"DBI can round-trip DATE columns as character depending
on the source,"* so the function defensively re-casts them to `Date` to
guarantee a stable, predictable output type regardless of quirks in how
DuckDB's DBI driver serializes dates.

**Why `setorder(...)` (line 190):** Deterministic row order. Without it, the
order of rows coming back from SQL isn't guaranteed, which would make output
comparisons (and tests) flaky.

---

## `long` output (lines 191–216)

```r
if (result_shape == "long") {
  required_long_cols <- c("person_id", "T0", "variable_id", "window_name", "date", "value")
  ...
  anchored_dt[, ..required_long_cols]
}
```

**What/why:** The simplest branch: just validate the expected columns exist
and return a subset. No population filtering happens here at all (notice
`population_keys_dt` isn't referenced in this branch): long format is
inherently unambiguous even with duplicate anchor keys, since every
variable/window gets its own row rather than its own column. The
population-filtering machinery below exists specifically to make *wide*
output well-defined, which is a much harder problem.

---

## `wide` output (lines 217–406)

This is the bulk of the function. It happens in stages:

### 1. Restrict to the population's keys (lines 218–226)

```r
if (!is.null(population_keys_dt)) {
  anchored_dt <- anchored_dt[population_keys_dt, on = .(person_id, T0), nomatch = 0L]
}
```

**Why:** The comment says it plainly: *"Restricting to the requested
population keeps wide output cardinality anchored to the caller's keys even
if the hive contains extra rows."* The parquet hive might contain anchored
values for people who aren't in the caller's population of interest (e.g., a
shared hive used across multiple studies). Filtering here, before casting,
ensures the wide table's rows correspond exactly to the population the
caller asked for, not everyone in the hive.

### 2. Guard against ambiguous wide casts (lines 228–259)

```r
duplicate_rows <- anchored_dt[, .N, by = .(person_id, T0, window_name, variable_id)][N > 1L]
if (nrow(duplicate_rows) > 0L) { ... stop(...) }
```

**Why:** `dcast` (next step) needs exactly one value per
`person_id`/`T0`/`window_name`/`variable_id` combination to produce a
well-defined cell. If the hive itself has more than one row for that exact
combination (the error message gives a concrete example: a selector like
`ALL` that returns multiple events instead of one), there's no sensible way
to pick a single value for that wide cell, so this is a hard `stop()`, not a
warning. This is a deliberate contrast with the `population` duplicate-key
case above: there, dropping to "first row wins" was a legitimate business
scenario; here, duplicate anchored values for the same variable/window/date
usually signal a genuine selector bug, and the fix is explicit (switch to
`result_shape = "long"`), so it's treated as an error rather than silently
resolved.

### 3. The actual pivot (lines 261–274)

```r
formula <- if (cast_window) "person_id + T0 ~ window_name + variable_id"
           else "person_id + T0 + window_name ~ variable_id"
wide_anchored <- data.table::dcast(anchored_dt, formula, value.var = ..., fill = ...)
```

**What:** Reshapes long rows into wide columns named `value_<variable_id>`
and `date_<variable_id>` (or `value_<window_name>_<variable_id>` when
`cast_window = TRUE`).

**Why two different formulas:** These serve two different mental models of
"one row per what." Default (`cast_window = FALSE`): one row per
person/date/window, useful when a person can have multiple meaningfully
distinct windows you want to keep as separate rows. `cast_window = TRUE`:
one row per person/date, with window folded into the column name instead,
useful when you want a single flat row per person, with e.g. both a
"30-day" and "90-day" value of the same variable sitting side by side as
different columns.

### 4. Backfilling columns that theoretically exist but had no data (lines 276–331)

```r
expected_date_cols <- ...
missing_date_cols <- setdiff(expected_date_cols, names(wide_anchored))
for (col_name in missing_date_cols) { wide_anchored[, (col_name) := as.Date(NA)] }
# ... same idea for value_ columns
```

**Why:** `dcast` only creates columns for combinations that actually appear
in the data. If a requested variable/window never occurred for *anyone* in
the filtered data, `dcast` won't produce that column at all, even
though the caller explicitly asked for it in `metadata`. Without this step,
the shape of the output would silently depend on what happened to be present
in the data, rather than on what was requested. This block guarantees every
requested variable (and window, if `cast_window`) gets a column, filled with
`NA` if there was no data.

### 5. Backfilling rows for population members with zero matching data (lines 333–391)

```r
expected_keys <- ... # every population_id/T0 (x window, if relevant) that *should* exist
missing_anchored <- data.table::fsetdiff(expected_keys, unique(wide_anchored[, ..result_key_cols]))
if (nrow(missing_anchored) > 0L) {
  wide_anchored <- data.table::rbindlist(list(wide_anchored, missing_anchored), use.names = TRUE, fill = TRUE)
}
```

**What:** This is the row-level counterpart to the previous column-level
step. It computes the full cross-product of "every population key" × "every
expected window" (when not `cast_window`), compares it against what's
actually in `wide_anchored`, and appends blank rows for any combination
that's missing entirely, e.g., a person in the population who had *no*
anchored data at all for any requested variable.

**Why it's this elaborate (the `.anchor_join_key` cartesian merge, lines
361–373):** Without `cast_window`, a "complete" row set isn't just
`population_keys_dt`; it's every population key crossed with every distinct
window that appears anywhere in the request (explicit windows from
`metadata`, plus any window names actually observed for wildcard variables).
`data.table` doesn't have a built-in "cross join" verb, so the code
manufactures one with a dummy `.anchor_join_key = 1` column and
`allow.cartesian = TRUE`, then discards the dummy key. The comment on line
383–384 states the payoff directly: *"Filling at the cast key guarantees a
deterministic number of rows for the requested population regardless of
which variables matched."* In other words: if you ask for 100 people, you
get 100 people back (times windows, if relevant), never fewer just because
some of them happened to have no data.

### 6. Optional imputation (lines 393–395)

```r
if (impute_missing == TRUE) {
  wide_anchored <- imputing_missing(wide_anchored, metadata_dt)
}
```

Delegates to `imputing_missing()` (see below). Deliberately placed *after*
all the column/row backfilling above, so imputation logic sees a fully
"square" table: every expected column and row already exists as `NA` where
there's no data, and imputation just needs to decide what to do with those
`NA`s.

### 7. Reattaching the population's extra columns (lines 397–404)

```r
if (!is.null(population_dt)) {
  wide_anchored <- population_dt[wide_anchored, on = .(person_id, T0)]
}
```

**What:** Joins the caller's original population columns (everything beyond
`person_id`/`T0`) back onto the now-finalized wide result.

**Why last:** The comment says it directly: *"Reattach the remaining
population columns once the wide result shape is stable, so they do not
interfere with filtering, casting, or imputation."* None of the earlier
steps (cast, column backfill, row backfill, imputation) need or want the
caller's extra columns along for the ride; keeping them out until the very
end avoids, e.g., `dcast` trying to do something with a `match_id` column, or
imputation logic having to know to ignore it.

**Why this is the step where duplicate-key handling actually matters, in
practice:** `population_dt` was deduplicated earlier (step 3 of the
population block) to exactly one row per `person_id`/`T0`. That's what makes
this a safe one-to-one join instead of a fan-out: if `population_dt` still
had two rows for the same key, this join would multiply the corresponding
row in `wide_anchored` into two rows, silently breaking the "one row per
person per date" invariant the entire wide-output machinery was built to
guarantee. This is the concrete, mechanical reason the earlier
dedup-with-warning exists: not just to tidy the input, but to make this join
safe. The flip side is that whatever extra information distinguished those
duplicate rows (e.g. which case a shared control was matched to) is the
price paid for that safety; only the first match's value survives into the
final output.

---

## `imputing_missing()` (lines 415–488)

```r
imputing_missing <- function(wide_anchored, metadata) { ... }
```

**What:** For each variable in `metadata`, looks at its `variable_type` and
`is_expected_missing` flag. If the variable is a boolean/logical type and
missingness *isn't* expected, missing cells are filled with `FALSE`. If it's
categorical, missing cells are filled with `0` (used as a "missing" category
code). Anything else (e.g. plain integers) is left untouched, since there's
no safe default numeric fill and the function declines to guess.

**Why `FALSE` specifically for booleans:** The comment states the domain
assumption: *"a boolean variable defaults to FALSE, since a missing record
means the subject never had that diagnosis."* This encodes a specific
epidemiological convention: absence of a record for a diagnosis/outcome
variable is treated as "didn't happen," not "unknown." That's a meaningful
modeling choice, not an arbitrary default; it only makes sense because it's
scoped to variables where `is_expected_missing` is *not* set (i.e., the
metadata author is asserting this variable *should* always have a value, so
its absence means "no" rather than "no data").

**Why check for partially-missing metadata columns and warn instead of
erroring (lines 446–460):** If `metadata` has *some* but not all of
`variable_id`/`is_expected_missing`/`variable_type`, that's very likely a
caller mistake (e.g. a typo'd column name) rather than "imputation wasn't
requested for this data," so it's flagged with a specific message naming
what's present vs. missing, and imputation is skipped rather than silently
doing nothing or crashing.

---

## Summary: the guiding principles running through the file

1. **Fail fast and specifically** for genuine caller mistakes (missing
   required columns, invalid `result_shape`, ambiguous wide-cast data):
   these get `stop()` with a message naming exactly what's wrong.
2. **Warn and continue** for situations that are valid in the domain but
   still require the function to make a judgment call (duplicate population
   keys from legitimate matching-with-replacement designs): these get
   `warning()` plus a description of the resolution strategy used.
3. **Guarantee deterministic shape.** The caller should get a predictable
   number of rows/columns based on what they *asked for* (population ×
   metadata), not based on incidental gaps in the underlying hive data. Most
   of the "wide" branch's complexity (backfilling columns, backfilling rows)
   exists to uphold this guarantee.
4. **Keep concerns separated until the shape is stable.** Population keys
   vs. population's extra columns, filtering vs. casting vs. imputation vs.
   reattachment all happen in a deliberate order so each step only has to
   reason about one thing at a time.
