SELECT
    w.anchor_row_id,
    w.person_id,
    w.T0,
    w.variable_id,
    w.window_name,
    CASE
        WHEN BOOL_OR(UPPER(COALESCE(CAST(c.value AS VARCHAR), 'TRUE')) = 'TRUE')
            THEN 'TRUE'
        ELSE 'FALSE'
    END AS value,
    MAX(c.date) AS date,
    COUNT(*) AS n
FROM population_windows AS w
INNER JOIN concepts AS c
    ON c.person_id = w.person_id
   AND c.concept_id = w.concept_id
   AND c.date BETWEEN w.window_start AND w.window_end
WHERE w.selector = 'IN_PREG_PRIOR_ANCHOREDPREG'
GROUP BY
    w.anchor_row_id,
    w.person_id,
    w.T0,
    w.variable_id,
    w.window_name
