SELECT
    w.anchor_row_id,
    w.variable_id,
    CAST(COUNT(*) AS VARCHAR) AS value,
    MAX(c.date) AS date,
    COUNT(*) AS n
FROM population_windows AS w
INNER JOIN concepts AS c
    ON c.person_id = w.person_id
   AND c.concept_id = w.concept_id
   AND c.date BETWEEN w.window_start AND w.window_end
WHERE w.selector = 'COUNT'
GROUP BY
    w.anchor_row_id,
    w.variable_id
