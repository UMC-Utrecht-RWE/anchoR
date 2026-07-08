WITH matches AS (
    SELECT
        w.anchor_row_id,
        w.person_id,
        w.T0,
        w.variable_id,
        w.window_name,
        COALESCE(CAST(c.value AS VARCHAR), 'TRUE') AS value,
        COALESCE(CAST(c.value AS VARCHAR), '') AS sort_value,
        c.date,
        -- Unordered window aggregates (no ORDER BY inside OVER) -- DuckDB
        -- computes these with a partitioned pass, not a sort, unlike the
        -- ROW_NUMBER() ... ORDER BY this replaces.
        COUNT(*) OVER (
            PARTITION BY w.person_id, w.T0, w.variable_id, w.window_name
        ) AS n,
        MIN(c.date) OVER (
            PARTITION BY w.person_id, w.T0, w.variable_id, w.window_name
        ) AS earliest_date
    FROM population_windows AS w
    INNER JOIN concepts AS c
        ON c.person_id = w.person_id
       AND c.concept_id = w.concept_id
       AND c.date BETWEEN w.window_start AND w.window_end
    WHERE w.selector = 'EARLIEST'
)
-- Earliest date wins, largest value breaks ties -- opposite directions on
-- the two fields, so (unlike LATEST) they can't collapse into one
-- lexicographic arg_min. Filtering to the already-known earliest_date first
-- keeps this second aggregation over just the (usually single-row) tied
-- subset instead of every candidate row.
SELECT
    arg_max(anchor_row_id, sort_value) AS anchor_row_id,
    person_id,
    T0,
    variable_id,
    window_name,
    arg_max(value, sort_value) AS value,
    MIN(date) AS date,
    MIN(n) AS n
FROM matches
WHERE date = earliest_date
GROUP BY person_id, T0, variable_id, window_name
