# Selector

The metadata `selector` determines how concept records inside the candidate window or windows are reduced. A selector can return zero, one, or multiple rows for a `person_id × T0 × variable_id × window_name` key.

Each selector is implemented by `inst/sql/<selector>.sql`. The query joins concepts to valid windows on `person_id`, `concept_id`, and inclusive `date BETWEEN window_start AND window_end`. When an episode constructor produces several candidate windows, the selector aggregates their joined matches into the same output key.

Candidate windows are not deduplicated before the join. If candidate windows overlap, one concept record can match more than one window row and therefore be counted or returned more than once. Episode data or window definitions should avoid overlap when distinct-event counts are required.

| selector | output |
| --- | --- |
| `LATEST` | Record on the latest matching date. |
| `EARLIEST` | Record on the earliest matching date. |
| `COUNT` | Number of matches as `value`; latest matching date as `date`. |
| `COUNT_MORE_THAN_1` | `value = "TRUE"` only for two or more matches; otherwise no row. |
| `RANGE_COUNT` | Count of records whose numeric value is within inclusive `[range_min, range_max]`; latest qualifying date as `date`. |
| `ALL` | Every matching record, one output row per record. |

A window with zero matches produces no persisted row for any selector. `COUNT` therefore does not persist zeroes; population-complete zero/false values can be introduced later in wide output using documented imputation rules.

`LATEST` and `EARLIEST` compare dates first. If records share the selected date, the lexicographically largest normalized character `value` breaks the tie. Null values are normalized consistently with selector output. This makes the result deterministic but may differ from numeric ordering (for example, `"9"` sorts after `"10"`); deduplicate upstream when another tie rule is scientifically required.

`available_selectors()` lists installed templates. Selector names are trimmed, normalized to upper case, and spaces/hyphens become underscores. `filter_supported_metadata()` can deliberately discard rows with missing or unsupported selectors; `anchor()` otherwise stops on them.
