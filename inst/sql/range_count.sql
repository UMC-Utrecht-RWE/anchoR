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
WHERE w.selector = 'RANGE_COUNT'
  AND w.range_min IS NOT NULL
  AND w.range_max IS NOT NULL
  AND TRY_CAST(c.value AS DOUBLE) BETWEEN w.range_min AND w.range_max
GROUP BY
    w.anchor_row_id,
    w.variable_id;
