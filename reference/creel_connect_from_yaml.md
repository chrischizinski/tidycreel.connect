# Create a creel connection from a YAML config file

`creel_connect_from_yaml()` reads a YAML configuration file and creates
a validated `creel_connection` object. All required keys and types are
validated before any connection is attempted (fail-fast).

Credentials must never be stored as plain text in the YAML file. Use the
`config` package's `!expr` tag to inject environment variables:

    username: !expr Sys.getenv("CREEL_USER")
    password: !expr Sys.getenv("CREEL_PASS")

### API profiles

With `backend: api`, the profile carries the whole API contract –
`base_url`, `uid_param`, `creel_uids`, `endpoints` and `field_map` –
because none of it ships with the package. A commented template with
invented names is installed at

    system.file("extdata", "api-profile-example.yml", package = "tidycreel.connect")

Keeping the profile outside your analysis code is what lets the same
script run against a different organisation's API by pointing at a
different file.

An optional `pagination:` block says how the API pages its responses and
is passed straight to
[`creel_connect_api()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect_api.md),
which documents the styles. Leave it out for an API that returns every
record at once – a response that proves otherwise then aborts rather
than being read as the complete dataset.

Two more optional keys describe the *shape* of a response rather than
the number of them. `records_path:` names the member holding the records
for an API that wraps them in an envelope, and `total_path:` names the
member holding the count for the whole query. Both are passed straight
to
[`creel_connect_api()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect_api.md).
Write a nested path as a sequence:

    records_path: results        # {"count": 42, "results": [...]}
    total_path: count

    records_path: [data, items]  # {"data": {"items": [...]}}

Leave them out for an API whose body is the JSON array itself.

### CSV profiles

The CSV backend resolves every canonical column through the schema, so
the profile has to say what your columns are called. Name them under
`schema: columns:`, keyed by tidycreel's canonical name with no `_col`
suffix:

    schema:
      survey_type: instantaneous
      columns:
        interview_uid: InterviewID
        date: SurveyDate
        effort: HoursFished

A column the source already names the way tidycreel does needs no entry:
the fetch takes it by its canonical name and says which columns it took
that way. Declare it anyway to state the mapping explicitly. A column
that is neither mapped nor canonically named is dropped on the way in,
which
[`fetch_interviews()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_interviews.md)
reports as a missing required column. Note that an entry naming a column
the source does not have stays a drop — it is not rescued by a
canonically-named column, because a mapping that does not match is a
configuration error worth seeing. A commented template is installed at

    system.file("extdata", "csv-profile-example.yml", package = "tidycreel.connect")

`backend: api` ignores column mappings and reads raw JSON keys from
`field_map`, so a `columns:` block there is an error rather than a
no-op.

`backend: sqlserver` resolves a `columns:` block exactly as `csv` does:
both read a whole table and rename it through the schema. It
additionally needs the table names, which the same `schema:` block
carries as `interviews_table`, `counts_table`, `catch_table` and
`harvest_lengths_table` / `release_lengths_table` (both falling back to
`lengths_table`).

### Time zone

An optional top-level `tz:` key names the time zone of the water, as one
IANA name from [`OlsonNames()`](https://rdrr.io/r/base/timezones.html):

    tz: America/Chicago

Night designs need one (see
[`tidycreel::creel_design()`](https://chrischizinski.com/tidycreel/reference/creel_design.html)),
and the profile is where the water is described, so it saves repeating
the zone in every script. The value is checked when the profile is read,
kept on the connection as `conn$tz`, and, when the `tidycreel.tz` option
is unset, set as that option for the session, with a one-line message
saying so. tidycreel reads a `tz =` argument before the option, so an
explicit argument always wins.

An option already set to a different zone is kept, with a warning: it
was set on purpose, perhaps by another profile, and replacing it
silently would move that water's night designs into this one's zone.
Pass `tz = conn$tz` to
[`tidycreel::creel_design()`](https://chrischizinski.com/tidycreel/reference/creel_design.html)
for the water this profile describes.

## Usage

``` r
creel_connect_from_yaml(path, config = "default")
```

## Arguments

- path:

  Path to the YAML config file. Must exist.

- config:

  Environment block to use (default: `"default"`). Passed to
  `config::get(config = ...)`. Common values: `"default"`,
  `"production"`, `"staging"`.

## Value

A `creel_connection` S3 object.

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- creel_connect_from_yaml("config.yml")
conn <- creel_connect_from_yaml("config.yml", config = "production")
} # }
```
