# Impute Missing Values in Wide Anchor Output

Fills in blank (`NA`) value\_\<variable_id\> cells in a wide anchored
result table, using `metadata` to decide what a blank cell should become
for each variable.

## Usage

``` r
imputing_missing(wide_anchored, metadata)
```

## Arguments

- wide_anchored:

  A wide data.table from get_anchor_result with value\_\<variable_id\>
  columns.

- metadata:

  A data frame that should include variable_id, is_expected_missing, and
  variable_type.

## Value

The updated wide data.table. Returns input unchanged when required
metadata columns are missing.

## Details

get_anchor_result() only produces a value when a matching record was
found, so a blank cell can mean different things depending on the kind
of variable. For a yes/no (boolean) variable, "no record found" usually
means the event never happened, so it should read as `FALSE` rather than
"unknown". For a categorical variable, "no record found" is usually its
own category. This function applies those defaults so callers do not
have to fill them in by hand for every variable.

For each `variable_id` listed in `metadata` (skipping any row where
`is_expected_missing` is `TRUE`, since those variables are allowed to
stay missing):

- Boolean/TF variable types (`TF`, `BOOL`, `BOOLEAN`, `LOGICAL`): blank
  cells become `FALSE`. `TRUE`/`FALSE` are recognized however they are
  stored as logicals, as numbers (`1`/`0`), or as text
  (`"TRUE"`/`"FALSE"`/`"T"`/`"F"`/`"1"`/`"0"`). Any other value is
  treated as invalid, logged with a warning, and defaulted to `TRUE`.

- Categorical variable types (`CAT`, `FACTOR`): blank cells become `0`,
  used as a dedicated "missing" category.

- Any other variable_type is left untouched.

If `metadata` is missing all three required columns (`variable_id`,
`is_expected_missing`, `variable_type`), imputation is skipped and the
input is returned unchanged. If only some of those columns are present,
the function warns and also skips imputation, rather than guessing at
the missing rules.
