# validate_anchor_inputs()

> Normalizes [[Population]], [[Metadata]], and [[Concepts]] into a consistent internal shape before any windowing or selector logic runs — the single place where input assumptions are enforced.

Does, in order: converts `population` to a data.table and coerces/validates its anchor column ([[Anchor Column (T0)]]) to `Date` (accepting a strict `YYYY-mm-dd` character format too); normalizes `metadata` via `normalize_metadata()` (column aliasing, defaults, type coercion — see [[Metadata]]); asserts `population` has `person_id` and `metadata` has the full standardized column set; checks every `anchor_start_col`/`anchor_end_col` referenced by metadata actually exists in `population`; checks every metadata `selector` is one [[Selector|`available_selectors()`]] supports (erroring otherwise, pointing at [[filter_supported_metadata()]] as an alternative); and, if `concepts` is supplied, classifies/validates it as a table, DuckDB file, or parquet source (see [[Concept Source Types]]).

Called by [[anchor()]], [[anchor_by_variable()]], and [[define_window()]] — so all three share one normalization path and can't drift out of sync.

## Related
- [[Population]]
- [[Metadata]]
- [[Concepts]]
- [[anchor()]]
- [[define_window()]]
- [[filter_supported_metadata()]]
