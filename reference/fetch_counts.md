# Load count data from a creel connection

Reads the counts table from a creel data source, renames columns to
canonical tidycreel names, coerces types, validates, and returns a data
frame ready for
[`tidycreel::add_counts()`](https://chrischizinski.com/tidycreel/reference/add_counts.html).

The result carries up to three numeric count columns, so
[`tidycreel::add_counts()`](https://chrischizinski.com/tidycreel/reference/add_counts.html)
cannot infer which one to expand into effort and will abort unless you
name it. `bank_anglers` counts anglers on shore; `angler_boats` and
`non_ang_boats` count boats, not anglers. Summing the three is therefore
not a total angler count – converting boats to anglers needs a mean
party size from the interviews, which is what
[`tidycreel::derive_angler_count()`](https://chrischizinski.com/tidycreel/reference/derive_angler_count.html)
applies:

    counts <- fetch_counts(conn)
    counts <- tidycreel::derive_angler_count(
      counts,
      bank       = bank_anglers,
      boat_count = angler_boats,
      party_size = mean_party_size   # from your interviews
    )
    design <- tidycreel::add_counts(design, counts, count_col = angler_count)

Naming `count_col = bank_anglers` instead is correct only on a fishery
with no boat anglers; anywhere else it drops that component of effort
silently.

## Usage

``` r
fetch_counts(conn, ...)
```

## Arguments

- conn:

  A `creel_connection` object created by
  [`creel_connect()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect.md).

- ...:

  Reserved for future arguments.

## Value

A data frame with canonical columns: `date` (Date), `bank_anglers`
(numeric), `angler_boats` (numeric), `non_ang_boats` (numeric), plus
`count_time` (character) and any stratum columns the schema maps.
Unmapped source columns are dropped.

On the API backend every row also carries `creel_uid` (character), the
creel UID it was fetched for, so a connection to several creels returns
them labelled rather than pooled.

When the API returns no rows, the result has no stratum columns. A fetch
with rows carries each stratum in the source's own type, which an empty
response does not reveal, and no zero-length guess binds with every type
in
[`dplyr::bind_rows()`](https://dplyr.tidyverse.org/reference/bind_rows.html).
Check for the column, or for `nrow() == 0`, before selecting a stratum.

## The grain of a count row

One row is one count observation, not a day's total. Sources commonly
record several counts on a sampled day, and it is the count time that
tells them apart. Map `count_time_col` (CSV/SQL) or the `count_time`
field (API field map) whenever the source records one, and pass the
fetched column to
[`tidycreel::add_counts()`](https://chrischizinski.com/tidycreel/reference/add_counts.html):

    design <- tidycreel::add_counts(
      design, counts,
      count_col      = angler_count,
      count_time_col = count_time
    )

Without it, repeat rows on a date reach the design as separate sampled
days: the day's effort is summed rather than averaged to a daily mean,
and the within-day variance component is never computed (GH \#129).
`fetch_counts()` warns when it returns repeat rows and no count time was
mapped.
