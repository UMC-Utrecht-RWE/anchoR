WITH date_level AS (
    SELECT
        w.anchor_row_id,
        w.person_id,
        w.T0,
        w.variable_id,
        w.window_name,
        c.date,
        COUNT(*) AS date_n,
        CAST(
            CASE
                WHEN COUNT(DISTINCT COALESCE(CAST(c.value AS VARCHAR), 'TRUE')) > 1
                    THEN 'unknown_edited_1'
                ELSE MAX(COALESCE(CAST(c.value AS VARCHAR), 'TRUE'))
            END AS VARCHAR
        ) AS value
    FROM population_windows AS w
    INNER JOIN concepts AS c
        ON c.person_id = w.person_id
       AND c.concept_id = w.concept_id
       AND c.date BETWEEN w.window_start AND w.window_end
    WHERE w.selector = 'DURING_PREG_AND_IN_ANCHOREDPREG'
    GROUP BY
        w.anchor_row_id,
        w.person_id,
        w.T0,
        w.variable_id,
        w.window_name,
        c.date
),
candidate_rows AS (
    SELECT
        anchor_row_id,
        person_id,
        T0,
        variable_id,
        window_name,
        value,
        date,
        SUM(date_n) OVER (PARTITION BY anchor_row_id) AS n,
        ROW_NUMBER() OVER (
            PARTITION BY anchor_row_id
            ORDER BY date DESC, value DESC
        ) AS row_number_
    FROM date_level
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
WHERE row_number_ = 1
