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

### Corrections

An optional top-level `corrections:` key names a CSV of documented fixes
to the fetched data, read relative to the profile's directory:

    corrections: corrections.csv

    creel_uid,table,date,field,from,to,reason
    ,counts,2025-06-14,period,1,2,Section 3 counted PM; sheet says AM

Each row changes `field` from `from` to `to` on the `table` records of
that `date` (`interviews` or `counts`; catch and lengths carry no date).
Names and values are tidycreel's, after `field_map`/`columns` and
`value_maps`. Every row needs a `reason`. Leave `creel_uid` blank on a
CSV or SQL Server profile, or on an API profile with one creel; name the
creel on an API profile with several. Rows for creels the profile does
not fetch are ignored, so one file can serve them all.

`NA` in `from` matches a missing value and in `to` writes one. Quote a
value that contains a comma.

[`fetch_interviews()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_interviews.md)
and
[`fetch_counts()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_counts.md)
apply them in file order, before validation, and list each change once
per connection (`creel_message_corrections_applied`) by line, date,
field and count. The values themselves are not printed, since one can be
personal (a ZIP code); keep the `reason` free of them too. The result
carries the rows applied, with the number of records each changed, as
`attr(x, "corrections")`, for a report to list. A correction that
matches no record is an error (`creel_error_correction_unmatched`): the
data changed underneath it, and it has to be checked again rather than
silently do nothing.

### Cleanup

An optional top-level `cleanup:` block removes rows that are artifacts
of how the source serves data rather than records. Every step is off
unless named `true`:

    cleanup:
      interviews:
        drop_placeholders: true
        collapse_repeats: true
      counts:
        drop_placeholders: true

`drop_placeholders` drops rows that carry a value in no column but
`creel_uid`, `date` and the strata: rows a source writes for a sampled
date on which nothing was recorded. A blank string counts as no value.
Rows are judged on the fetched columns, so a source column that holds
data the analysis needs must be mapped to count. A blank count row is
dropped, never read as a zero. An interview row with no `interview_uid`
that does carry data is an error
(`creel_error_cleanup_rows_without_uid`), not a placeholder.

`collapse_repeats` keeps one of each set of interview rows identical in
every fetched column: a long-format source repeats each interview once
per questionnaire answer, which
[`fetch_interviews()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_interviews.md)
otherwise warns about (`creel_warning_fetch_created_duplicates`) and
returns. If one interview still has two rows that differ, the fetch
aborts (`creel_error_cleanup_conflicting_repeats`) and names the
columns, since choosing one would be a guess. Rows with no
`interview_uid` are refused before collapsing
(`creel_error_cleanup_rows_without_uid`), since nothing says identical
ones are one interview; set `drop_placeholders` too when they are
placeholders. Counts have no `collapse_repeats`: two identical count
rows can be two real counts.

Cleanup runs after corrections. The fetch reports what it removed once
per connection (`creel_message_rows_cleaned`), and the result carries
the counts as `attr(x, "cleanup")`: `rows_in`, `placeholders_dropped`,
`repeats_collapsed` and `rows_kept`.

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
