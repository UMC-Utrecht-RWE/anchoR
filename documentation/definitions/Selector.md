> The metadata `selector` value that decides how to collapse the [[Concepts|concept]] records matching one person-variable [[Window]] into a single result row (or several, for `ALL`).

Each selector is a named SQL template in `inst/sql/<selector>.sql`, joining `concepts` to `population_windows` on `person_id`, `concept_id`, and `date BETWEEN window_start AND window_end`, then aggregating per `person_id x T0 x variable_id x window_name`. `available_selectors()` lists whichever templates are bundled; `filter_supported_metadata()` can drop metadata rows whose selector isn't one of them.

Built-in selectors:
- LATEST: most recent matching record
- EARLIEST: oldest matching record
- COUNT: count of matches (value is the count)
> Returns how many [[Concepts|concept]] records matched a [[Window]]; `value` is that count (as a string), `date` is the latest matching date.
- COUNT_MORE_THAN_1 : `TRUE` only with 2+ matches, else no row
  > Returns `value = "TRUE"` only when 2 or more [[Concepts|concept]] records matched a [[Window]]; a person with 0 or exactly 1 match gets no row at all.
- RANGE_COUNT: count of matches with a numeric value inside `[range_min, range_max]`
  > Returns the count of matching [[Concepts|concept]] records whose numeric `value` falls inside `[range_min, range_max]`, the count is the output `value`, not the underlying measurement.
- ALL: every matching record, one output row each.
  > Returns every matching [[Concepts|concept]] record in a [[Window]], one output row per record, the only selector that can produce more than one row per `person_id x T0 x variable_id x window_name`.

A window with zero matching concept records produces no row for any selector.