# Filter Metadata to Selectors Supported by the Package

Keeps only metadata rows whose selector has a bundled SQL template in
the package. Rows with missing or unsupported selectors are dropped with
a warning.

## Usage

``` r
filter_supported_metadata(metadata, selector_col = "selector")
```

## Arguments

- metadata:

  A data frame containing study-variable metadata.

- selector_col:

  Column in `metadata` that contains selector names.

## Value

A filtered `data.table` with the same columns as the input.
