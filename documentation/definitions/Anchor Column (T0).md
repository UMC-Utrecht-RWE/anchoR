Passed to [[anchor()]] / [[anchor_by_variable()]] / [[define_window()]] as `anchor_col`. 

If a population's index date is named something else (e.g. `index_date`), pass its name via `anchor_col` — the [[Anchored Result|output]] still writes it under the column `T0` regardless.

Individual metadata rows can override this per-variable via `anchor_start_col`/`anchor_end_col` (aliased from `anchor_date_start`/`anchor_date_end`), which is how a single metadata table can mix ordinary `T0`-anchored variables with variables anchored to other dates (or, for episode-based windows, to an episode's own start/end). The literal string `"T0"` in these columns is treated as a symbolic placeholder that always resolves to whatever `anchor_col` actually is.

`population$T0` (or whichever column is used) must be a `Date`, or a character column in strict `YYYY-mm-dd` format — `validate_anchor_inputs()` coerces and errors otherwise.