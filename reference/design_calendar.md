# Build a design calendar from a creel's design tables and counts

`design_calendar()` turns the tables
[`fetch_design()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_design.md)
returns, and the counts that say which days were worked, into the
calendar
[`tidycreel::creel_design()`](https://chrischizinski.com/tidycreel/reference/creel_design.html)
takes: every day of the season with its stratum and, on each worked day,
the shift drawn, its window, its real length and its selection
probability.

The design tables say what *could* be drawn: the shift windows and their
probabilities by month. Which days were sampled, and which shift was
drawn on each, only the counts say: a day with counts is a worked day,
and the counts' `period_col` names the shift worked.

## Usage

``` r
design_calendar(
  design,
  counts,
  period_col = "period",
  creel_uid = NULL,
  special_dates = NULL,
  day_start = NULL,
  tz = getOption("tidycreel.tz")
)
```

## Arguments

- design:

  The list returned by
  [`fetch_design()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_design.md).

- counts:

  Counts for the same creel, as returned by
  [`fetch_counts()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_counts.md):
  a `date` column and the drawn shift in `period_col`.

- period_col:

  Name of the counts column holding the shift drawn on each day, matched
  to the design's `period_id`. Usually carried through the profile's
  `strata_cols:`.

- creel_uid:

  The creel to build the calendar for. Required when `design` holds more
  than one; counts with a `creel_uid` column are filtered to it.

- special_dates:

  The special-date rule: `"stratum"`, `"weekend"` or `"ignore"`, or
  `NULL` to take it from the design.

- day_start:

  For a night design, the clock time (`"HH:MM"`) at which a survey day
  begins, or `NULL` for the earliest shift start every shift fits after.
  Not `"00:00"`. Ignored for a design with no shift crossing midnight.

- tz:

  For a night design, the time zone of the water, one name from
  [`OlsonNames()`](https://rdrr.io/r/base/timezones.html): a night
  across a daylight-saving change is an hour longer or shorter than its
  clock times. Defaults to the `tidycreel.tz` option, which a profile's
  `tz:` sets.

## Value

A data frame with one row per day of the season: `date`, `month`
(integer), `day_type`, `stratum`, and the drawn shift on worked days
(`NA` on the others): `period_id`, `p_period`, `shift_start`,
`shift_end` (`"HH:MM"`) and `shift_hours`. A night design adds
`day_start`.

## Strata

Ordinary days are stratified by month x day type (`weekday`, `weekend`).
Special dates follow the rule in `special_dates`:

- `"stratum"`: each special-date group is a stratum of its own, not
  split by month, with day type `special`;

- `"weekend"`: special dates join the weekend of their month;

- `"ignore"`: special dates are ordinary days.

Left `NULL`, the rule is the design's own: the `special_as_stratum` and
`special_as_weekend` flags of the general table, named in the profile's
`field_map:`. A design with special dates and neither flag is refused
rather than guessed.

## Shifts

`shift_hours` is the **real** length of the drawn shift and `p_period`
its probability, kept apart: tidycreel divides by `p_period` itself, so
pass `shift_hours` to
[`tidycreel::add_counts()`](https://chrischizinski.com/tidycreel/reference/add_counts.html)
as it is. A length already divided by the probability would apply it
twice.

A day with counts in more than one shift has no single probability and
is refused (`creel_error_calendar_two_shifts`), with the days listed: a
day worked off-design is fixed in the profile's corrections file, not
guessed. So is a count with no shift, a shift the month's design does
not have, and a count outside the season.

## Night designs

When a shift crosses midnight the design is a night design, and the
calendar carries `day_start`, the clock time at which each survey day
begins (see
[`tidycreel::creel_design()`](https://chrischizinski.com/tidycreel/reference/creel_design.html)).
It defaults to the earliest shift start, other than midnight, that every
shift fits inside a survey day from; tidycreel reads a survey day
starting at 00:00 as a day design. `shift_hours` is then each night's
elapsed time in `tz`, so a night across a daylight-saving change is
longer or shorter than its clock times, as tidycreel computes it; a
shift that starts or ends in a skipped or repeated time is refused.

A night is labelled by the date it began, and a count's `date` and
`count_time` are when it was made, as tidycreel reads them: a count
before `day_start` belongs to the night before, so a 00:15 count dated 1
July works the night of 30 June. A night design therefore needs each
count's `count_time` as a clock time (`"HH:MM"`).

Sections are not used: the calendar is per day.
