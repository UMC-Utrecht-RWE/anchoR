# Window Name

> The `window_name` metadata column that labels one of several windows defined for the same `variable_id` (e.g. `"lookback"`, `"risk"`, `"induction"`, or a free-text label like `"recent"` / `"ever"`).

A single study variable can need more than one window — a "how recent" view and an "ever" view of the same [[Identifiers (person_id, concept_id, variable_id)|concept]], for instance. anchoR supports this by letting the same `variable_id` repeat across metadata rows with different `window_name` (and usually different offsets/[[Selector|selector]]).

In [[Long Output]], `window_name` is always its own column. In [[Wide Output]], it behaves differently depending on [[cast_window]]: with the default `cast_window = FALSE`, `window_name` stays a row-key column (`person_id + T0 + window_name`, cast only on `variable_id`); with `cast_window = TRUE`, it's folded into the column name instead (`value_<window_name>_<variable_id>`), collapsing to one row per `person_id + T0`.

## Related
- [[Metadata]]
- [[Wide Output]]
- [[Long Output]]
- [[cast_window]]
