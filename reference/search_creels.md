# Search available creel surveys by keyword

Calls
[`list_creels()`](https://chrischizinski.com/tidycreel.connect/reference/list_creels.md)
and filters the result client-side to surveys whose `title` or
`description` contains `keyword` (case-insensitive). Not supported for
CSV or SQL Server connections.

## Usage

``` r
search_creels(conn, keyword, ...)
```

## Arguments

- conn:

  A `creel_connection` object created by
  [`creel_connect_api()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect_api.md).

- keyword:

  A single non-empty character string to search for.

- ...:

  Reserved for future arguments.

## Value

A data frame with the same column shape as
[`list_creels()`](https://chrischizinski.com/tidycreel.connect/reference/list_creels.md),
filtered to matching surveys.
