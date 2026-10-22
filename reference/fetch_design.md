# Load a creel's design tables from an API connection

Many agency creel APIs serve the survey's own design alongside its data:
the season, the shift windows with their selection probabilities, the
sections and the special dates. `fetch_design()` reads them through the
same profile as the data, renames them to canonical columns and returns
them as a list, so a calendar can be built from what the design says
rather than recomputed by hand.

Like every other endpoint, the design endpoints and their field names
are the caller's to declare: add `design_general`, `design_periods` and,
optionally, `design_sections` and `design_special_dates` to `endpoints`
and to `api_field_map` (or the profile's `endpoints:` and `field_map:`).

## Usage

``` r
fetch_design(conn, ...)
```

## Arguments

- conn:

  A `creel_connection` created by
  [`creel_connect_api()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect_api.md)
  or
  [`creel_connect_from_yaml()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect_from_yaml.md).

- ...:

  Reserved for future arguments.

## Value

A named list of data frames, each with `creel_uid`, the creel UID it was
fetched for:

- `general`: one row per creel. `season_start`, `season_end` (Date), and
  the special-date rule as two logical flags: `special_as_stratum`
  (special dates form strata of their own) and `special_as_weekend`
  (special dates join the weekend), each carried when mapped.

- `periods`: one row per month and period. `month` (integer),
  `period_id` (character), `start_time`, `end_time` (character,
  `"HH:MM"`), `length_hours` (numeric, from the clock times),
  `crosses_midnight` (logical), `p_period` (numeric, in (0, 1\]), and
  `stored_length_hours` when the source stores one.

- `sections`: `section` (character), or `NULL` when no `design_sections`
  endpoint is configured.

- `special_dates`: `date` (Date) and `group` (character, when mapped),
  or `NULL` when no `design_special_dates` endpoint is configured.

## Shift lengths

Each period's length is computed from its start and end clock times,
adding a day when the end is not after the start: a shift that crosses
midnight. The length the source stores is kept beside it as
`stored_length_hours`, and every period where the two disagree is
reported with a warning (`creel_warning_design_length_disagrees`) rather
than one silently preferred. A stored length computed as end - start on
a clock that wraps (a 19:30-00:30 shift stored as -19 h) has reached
published reports; this is the check that catches it. `crosses_midnight`
marks the shifts that make a night design (see
[`tidycreel::creel_design()`](https://chrischizinski.com/tidycreel/reference/creel_design.html)).

These are the **real** shift lengths. tidycreel divides by `p_period`
itself, so a length already divided by the probability must never be
passed to
[`tidycreel::add_counts()`](https://chrischizinski.com/tidycreel/reference/add_counts.html).
