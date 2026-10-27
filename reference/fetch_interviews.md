# Load interview data from a creel connection

Reads the interviews table from a creel data source, renames columns to
canonical tidycreel names, coerces types, validates, and returns a data
frame ready for
[`tidycreel::add_interviews()`](https://chrischizinski.com/tidycreel/reference/add_interviews.html).

## Usage

``` r
fetch_interviews(conn, ...)
```

## Arguments

- conn:

  A `creel_connection` object created by
  [`creel_connect()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect.md).

- ...:

  Reserved for future arguments.

## Value

A data frame with canonical columns: `interview_uid`, `date` (Date),
`catch_count` (numeric), `effort` (numeric), `trip_status` (character).

Six further columns are carried when the schema (CSV) or `api_field_map`
(API) maps them, and omitted otherwise: `n_anglers` (numeric),
`angler_type` (character), `site` (character), `circuit` (character),
`n_counted` (numeric), `n_interviewed` (numeric). Map `n_anglers`
whenever the source records party size – without it
[`tidycreel::add_interviews()`](https://chrischizinski.com/tidycreel/reference/add_interviews.html)
assumes one angler per interview and party-hours are consumed as
angler-hours. `site` and `circuit` are what a bus-route design joins the
site inclusion probability on.

Four more are carried on the same terms for the tidycreel summaries:
`angler_method` (character), `species_sought` (character), `refused`
(logical) and `zip_code` (character). `refused` accepts TRUE/FALSE, T/F,
yes/no, Y/N and 1/0 in any case, and aborts on any other code rather
than reading it as `NA`; pass it to
[`tidycreel::add_interviews()`](https://chrischizinski.com/tidycreel/reference/add_interviews.html)
so a refused interview is not taken for a no-catch party. `zip_code` is
written as text, with a whole number padded back to five digits.
`angler_method` and `species_sought` are carried as the source codes
them: `value_maps` does not cover them, because tidycreel has no
canonical vocabulary for either. On CSV and SQL,
[`tidycreel::creel_schema()`](https://chrischizinski.com/tidycreel/reference/creel_schema.html)
has no `zip_code_col`, so `zip_code` is carried only from a source
column already named `zip_code`.

Source columns outside the map are dropped, and each fetch reports which
ones by name.

A profile's `cleanup:` block can drop placeholder rows and collapse a
long-format source's repeated rows to one per interview; see
[`creel_connect_from_yaml()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect_from_yaml.md).
Without it, rows are returned as the source serves them.

On the API backend every row also carries `creel_uid` (character), the
creel UID it was fetched for, so a connection to several creels returns
them labelled rather than pooled.

When the API returns no rows, the result has no stratum columns. A fetch
with rows carries each stratum in the source's own type, which an empty
response does not reveal, and no zero-length guess binds with every type
in
[`dplyr::bind_rows()`](https://dplyr.tidyverse.org/reference/bind_rows.html).
Check for the column, or for `nrow() == 0`, before selecting a stratum.
