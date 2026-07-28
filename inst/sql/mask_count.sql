SELECT
    w.person_id,
    w.T0,
    w.variable_id,
    w.window_name,
    CAST(
        CASE
            WHEN COUNT(*) = 0 THEN 1      -- count of 0 -> assign 1
            WHEN COUNT(*) IN (1, 2) THEN 2 -- count of 1 or 2 -> assign 2
            WHEN COUNT(*) IN (3, 4) THEN 3 -- count of 3 or 4 -> assign 3
            WHEN COUNT(*) >= 5 THEN 4     -- count of >= 5 -> assign 4
        END AS VARCHAR
    ) AS value,
    MAX(c.date) AS date,
    COUNT(*) AS n
FROM population_windows AS w
INNER JOIN concepts AS c
    ON c.person_id = w.person_id
   AND c.concept_id = w.concept_id
   AND c.date BETWEEN w.window_start AND w.window_end
WHERE w.selector = 'MASK_COUNT'
GROUP BY
    w.person_id,
    w.T0,
    w.variable_id,
    w.window_name
