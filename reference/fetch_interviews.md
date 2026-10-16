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

Source columns outside the map are dropped, and each fetch reports which
ones by name.
