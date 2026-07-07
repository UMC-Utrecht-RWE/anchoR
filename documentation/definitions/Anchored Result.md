> The output of anchoR: one anchored value and event date per `person_id x T0 x variable_id x window_name` combination that actually matched something.

Produced by [[anchor()]] and read back by [[get_anchor_result()]], which reshapes it into either [[Long Output]] or [[Wide Output]].

The result is sparse by design: a person-variable combination with no matching [[Concepts|concept]] record inside its [[Window]] simply produces no row, rather than a row with a missing value. This is true in both long and wide shapes, and is why `get_anchor_result(..., population = population)` exists for wide output, it backfills the population's full key set so "no match" becomes a visible `NA` instead of a silently absent row.

The result never carries through extra [[Population]] columns like `match_id`, `boot_id`, or `group` unless `population` is explicitly passed to `get_anchor_result()`.