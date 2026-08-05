> The input table of study units to be anchored: one row per person (or per `person_id x T0`), carrying the anchor date(s) `anchor()` windows against.

Unlike a long "anchor type / anchor date" table, anchoR's population is wide: each row is a person (or a person at a matched/bootstrapped instance) with one or more date columns. 

The core anchoring step requires `person_id`, the column named by `anchor_col` (`"T0"` by default), and any additional anchor or episode columns referenced by metadata. Other fields such as `match_id`, `boot_id`, `group`, and pre-computed covariates are ignored by `anchor()` itself. They are reattached to wide results when the same population is passed to `get_anchor_result()`; they are not persisted in the anchor hive or included in long output.

If a non-`T0` column is used as the anchor (via `anchor_col`), the output still reports it under the column name `T0`.

Episode-based constructors additionally need a separate [Episodes](Episodes.md) table, passed as `define_window()`/`anchor()`'s own `episodes` argument rather than as a population column; anchoR nests it onto `population` internally. See [Episode-Based Window Engine](<Episode-Based Window Engine.md>).
