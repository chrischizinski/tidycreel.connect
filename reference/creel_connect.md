# Create a creel database or file connection

`creel_connect()` creates a validated `creel_connection` S3 object that
`fetch_*()` functions dispatch on. Two backends are supported:

- **DBI backend:** pass any `DBIConnection` object (e.g., from
  [`DBI::dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html)
  with the `odbc` or `duckdb` driver).

- **CSV backend:** pass a named list with keys `interviews`, `counts`,
  `catch`, `harvest_lengths`, `release_lengths` pointing to CSV file
  paths. File existence is checked immediately at connection creation.

Both backends load data. A DBI connection reads each table by the name
the schema gives it (`interviews_table`, `counts_table`, `catch_table`,
and `harvest_lengths_table` / `release_lengths_table`, which fall back
to `lengths_table`); a table with no name in the schema cannot be
fetched.

A table name may be a string or a
[`DBI::Id()`](https://dbi.r-dbi.org/reference/Id.html). Use `Id()` for a
schema-qualified table —
`DBI::Id(schema = "dbo", table = "vwInterviews")` — because the string
`"dbo.vwInterviews"` is treated as one literal name and will not be
found.

### Connections are read-only

Nothing in this package writes. A connection only ever reads: no table
is created, altered, dropped or written to, no row is inserted or
updated, and no file is written — including the CSV files a connection
reads. Pointing a connection at a production database or an agency's
live export cannot modify it.

## Usage

``` r
creel_connect(con, schema)
```

## Arguments

- con:

  A `DBIConnection` object (DBI backend) or a named list of CSV file
  paths (CSV backend). For the CSV backend the list must contain keys:
  `interviews`, `counts`, `catch`, `harvest_lengths`, `release_lengths`.

- schema:

  A `creel_schema` object created by
  [`tidycreel::creel_schema()`](https://chrischizinski.com/tidycreel/reference/creel_schema.html).

## Value

A `creel_connection` S3 object.

## Examples

``` r
if (FALSE) { # \dontrun{
schema <- tidycreel::creel_schema(
  survey_type = "instantaneous",
  interviews_table = "interviews",
  counts_table = "counts"
)
paths <- list(
  interviews      = "data/interviews.csv",
  counts          = "data/counts.csv",
  catch           = "data/catch.csv",
  harvest_lengths = "data/harvest_lengths.csv",
  release_lengths = "data/release_lengths.csv"
)
conn <- creel_connect(paths, schema)
} # }
```
