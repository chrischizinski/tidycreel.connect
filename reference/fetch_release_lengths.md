# Load release length data from a creel connection

Reads the release lengths table from a creel data source, renames
columns to canonical tidycreel names, coerces types, validates, and
returns a data frame ready for
[`tidycreel::add_lengths()`](https://chrischizinski.com/tidycreel/reference/add_lengths.html).

## Usage

``` r
fetch_release_lengths(conn, ...)
```

## Arguments

- conn:

  A `creel_connection` object created by
  [`creel_connect()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect.md).

- ...:

  Reserved for future arguments.

## Value

A data frame with canonical columns: `length_uid`, `interview_uid`,
`species` (character), `length_type` (character), and a length:
`length_mm` (numeric) for measured fish, or `length_bin` (character)
with `count` (numeric) for binned rows. At least one of the two must be
mapped; the binned pair is carried only when the source names it (GH
\#127). Extra CSV columns are dropped.

On the API backend every row also carries `creel_uid` (character), the
creel UID it was fetched for, so a connection to several creels returns
them labelled rather than pooled.
