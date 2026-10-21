# Warning and message classes

Every warning tidycreel.connect raises has a class, so one can be
handled in one call without silencing the others. The classes follow
tidycreel's (see
[tidycreel::creel_warnings](https://chrischizinski.com/tidycreel/reference/creel_warnings.html)):
each warning carries its own class, `creel_warning_<fact>`, and the
parent `creel_warning`; information that is not a warning is raised as a
message with a class `creel_message_<fact>` and the parent
`creel_message`. A fact tidycreel also raises has tidycreel's class, so
one handler covers both packages.

Handle one for one call with
[`withCallingHandlers()`](https://rdrr.io/r/base/conditions.html):

    withCallingHandlers(
      fetch_interviews(conn),
      creel_message_columns_dropped = function(m) invokeRestart("muffleMessage")
    )

Prefer this to
[`suppressWarnings()`](https://rdrr.io/r/base/warning.html) or
[`suppressMessages()`](https://rdrr.io/r/base/message.html), which also
hide the warnings that mean the fetched data are not what the source
holds.

## Tiers

- Tier 1:

  The fetched data may be wrong for estimation.

- Tier 2:

  Worth a look; no estimate is affected.

- Tier 3:

  Information, raised as a message rather than a warning.

Warnings (tiers 1 and 2) print on every call. The two tier-3 notes about
the source's columns, `creel_message_columns_dropped` and
`creel_message_columns_by_canonical_name`, describe the source rather
than one fetch, so they print once per connection: the first fetch of a
table prints them, later fetches of that table on the same connection do
not, unless the columns differ. A new connection prints them again.
Other tier-3 messages print on every call. Unlike tidycreel, connect
returns data frames rather than designs, so nothing is recorded for
[`tidycreel::get_warnings()`](https://chrischizinski.com/tidycreel/reference/get_warnings.html).

## Warnings

- `creel_warning_dates_coerced_na`:

  Tier 1. Some dates could not be parsed and became `NA`.

- `creel_warning_numeric_coerced_na`:

  Tier 1. Some values of a numeric column could not be read as numbers
  and became `NA`.

- `creel_warning_fetch_created_duplicates`:

  Tier 1. The fetch made interview rows exact duplicates, so each copy
  counts that interview again: usually by dropping unmapped columns of a
  long-format source, sometimes by coercing or mapping values to the
  same value.

- `creel_warning_repeated_sampling_units`:

  Tier 1. Counts have repeated dates with no count time to tell them
  apart.

- `creel_warning_tz_option_differs`:

  Tier 1. A profile's `tz:` differs from the `tidycreel.tz` option
  already set, which is kept, so a night design given no `tz` is read in
  the option's zone, not the profile's. See
  [`creel_connect_from_yaml()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect_from_yaml.md).

- `creel_warning_bins_without_count`:

  Tier 1. Length bins were fetched without a fish count, so a
  distribution built from them is weighted by rows, not fish.

- `creel_warning_discovery_field_missing`:

  Tier 2. The discovery response lacks an expected field, which is
  filled with `NA`.

- `creel_warning_odbc_drivers_unlisted`:

  Tier 2.
  [`creel_check_driver()`](https://chrischizinski.com/tidycreel.connect/reference/creel_check_driver.md)
  could not list the ODBC drivers.

## Messages (tier 3)

- `creel_message_argument_ignored`:

  Tier 3. An argument has no effect in this call: `schema` column
  mappings on the API backend.

- `creel_message_columns_by_canonical_name`:

  Tier 3. Unmapped source columns were taken because they already carry
  a canonical name. Once per connection.

- `creel_message_columns_dropped`:

  Tier 3. Source columns not mapped are not carried through. Once per
  connection.

- `creel_message_tz_option_set`:

  Tier 3. A profile's `tz:` set the `tidycreel.tz` option, which was
  unset, for the session.
