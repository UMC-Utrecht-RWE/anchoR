# Combine the Episodes table onto Population, one list-column per person

Each population row gets its own person's episodes as a small
`data.table(start_episode, end_episode)`, forming a '3D structure' so
the. Persons with no episodes get a zero-row table rather than `NULL`.

## Usage

``` r
nest_episodes_onto_population(population_dt, episodes_dt)
```

## Arguments

- population_dt:

  A data.table with a `person_id` column.

- episodes_dt:

  A data.table with `person_id`, `start_episode`, `end_episode` columns
  (already validated).

## Value

`population_dt`, with `.episodes` added.
