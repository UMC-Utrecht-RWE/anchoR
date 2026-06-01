WITH candidate_rows AS (
    SELECT
        w.anchor_row_id,
        w.person_id,
        w.T0,
        w.variable_id,
        w.window_name,
        COALESCE(CAST(c.value AS VARCHAR), 'TRUE') AS value,
        c.date,
        COUNT(*) OVER (PARTITION BY w.anchor_row_id) AS n
    FROM population_windows AS w
    INNER JOIN concepts AS c
        ON c.person_id = w.person_id
       AND c.concept_id = w.concept_id
       AND c.date BETWEEN w.window_start AND w.window_end
    WHERE w.selector = 'ALL'
)
SELECT
    anchor_row_id,
    person_id,
    T0,
    variable_id,
    window_name,
    value,
    date,
    n
FROM candidate_rows
