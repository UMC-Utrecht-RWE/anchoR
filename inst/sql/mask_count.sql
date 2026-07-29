WITH raw_counts AS (
    SELECT
        w.person_id,
        w.T0,
        w.variable_id,
        w.concept_id,
        w.window_name,
        COUNT(*) AS raw_count,
        MAX(c.date) AS date
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
        w.concept_id,
        w.window_name
)
SELECT
    rc.person_id,
    rc.T0,
    rc.variable_id,
    rc.window_name,
    CAST(CAST(cr.new_value AS BIGINT) AS VARCHAR) AS value,
    rc.date,
    rc.raw_count AS n
FROM raw_counts AS rc
INNER JOIN concept_ranges AS cr
    ON cr.concept_id = rc.concept_id
   AND rc.raw_count BETWEEN cr.lower_range AND cr.upper_range
