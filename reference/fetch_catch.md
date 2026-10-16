# Load catch data from a creel connection

Reads the catch table from a creel data source, renames columns to
canonical tidycreel names, coerces types (including species to
character), validates, and returns a data frame ready for
[`tidycreel::add_catch()`](https://chrischizinski.com/tidycreel/reference/add_catch.html).

## Usage

``` r
fetch_catch(conn, ...)
```

## Arguments

- conn:

  A `creel_connection` object created by
  [`creel_connect()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect.md).

- ...:

  Reserved for future arguments.

## Value

A data frame with canonical columns: `catch_uid`, `interview_uid`,
`species` (character), `catch_count` (numeric), `catch_type`
(character). Extra CSV columns are dropped.
