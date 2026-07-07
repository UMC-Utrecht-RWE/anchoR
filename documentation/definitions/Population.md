> The input table of study units to be anchored: one row per person (or per `person_id x T0`), carrying the anchor date(s) `anchor()` windows against.

Unlike a long "anchor type / anchor date" table, anchoR's population is wide: each row is a person (or a person at a matched/bootstrapped instance) with one or more date columns. The only hard requirements for the core anchoring step are `person_id` and the column named by `anchor_col` (`"T0"` by default). Everything else — `match_id`, `boot_id`, `group`, pre-computed covariates — is allowed but ignored by `anchor()` itself, and is **not** carried through into [[Anchored Result]].

If a non-`T0` column is used as the anchor (via `anchor_col`), [[Anchored Result|the output]] still reports it under the column name `T0`.