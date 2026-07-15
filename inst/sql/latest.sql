WITH winners AS (
    SELECT
        w.person_id,
        w.T0,
        w.variable_id,
        w.window_name,
        -- Both fields sort DESC (latest date, then largest value on ties),
        -- so one lexicographic arg_max on (date, value) picks the same row a
        -- ROW_NUMBER() ORDER BY date DESC, value DESC filter would, without
        -- needing to sort every candidate row.
        arg_max(
            struct_pack(
                value := COALESCE(CAST(c.value AS VARCHAR), 'TRUE'),
                date := c.date
            ),
            struct_pack(
                date := c.date,
                value := COALESCE(CAST(c.value AS VARCHAR), '')
            )
        ) AS winner
    FROM population_windows AS w
    INNER JOIN concepts AS c
        ON c.person_id = w.person_id
       AND c.concept_id = w.concept_id
       AND c.date BETWEEN w.window_start AND w.window_end
    WHERE w.selector = 'LATEST'
    GROUP BY w.person_id, w.T0, w.variable_id, w.window_name, w.date, w.value
)
SELECT
    person_id,
    T0,
    variable_id,
    window_name,
    winner.value AS value,
    winner.date AS date
FROM winners
