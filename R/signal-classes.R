#' Warning and message classes
#'
#' @description
#' Every warning tidycreel.connect raises has a class, so one can be handled in
#' one call without silencing the others. The classes follow tidycreel's (see
#' [tidycreel::creel_warnings]): each warning carries its own class,
#' `creel_warning_<fact>`, and the parent `creel_warning`; information that is
#' not a warning is raised as a message with a class `creel_message_<fact>` and
#' the parent `creel_message`. A fact tidycreel also raises has tidycreel's
#' class, so one handler covers both packages.
#'
#' Handle one for one call with [withCallingHandlers()]:
#'
#' ```r
#' withCallingHandlers(
#'   fetch_interviews(conn),
#'   creel_message_columns_dropped = function(m) invokeRestart("muffleMessage")
#' )
#' ```
#'
#' Prefer this to [suppressWarnings()] or [suppressMessages()], which also
#' hide the warnings that mean the fetched data are not what the source holds.
#'
#' @section Tiers:
#' \describe{
#'   \item{Tier 1}{The fetched data may be wrong for estimation.}
#'   \item{Tier 2}{Worth a look; no estimate is affected.}
#'   \item{Tier 3}{Information, raised as a message rather than a warning.}
#' }
#' Warnings (tiers 1 and 2) print on every call. The tier-3 notes about the
#' source, \code{creel_message_columns_dropped},
#' \code{creel_message_columns_by_canonical_name},
#' \code{creel_message_corrections_applied} and
#' \code{creel_message_rows_cleaned}, describe the source rather than
#' one fetch, so they print once per connection: the first fetch of a
#' table prints them, later fetches of that table on the same connection do
#' not, unless the columns differ. A new connection prints them again. Other
#' tier-3 messages print on every call. Unlike tidycreel, connect returns data
#' frames rather than designs, so nothing is recorded for
#' [tidycreel::get_warnings()].
#'
#' @section Warnings:
#' \describe{
#'   \item{\code{creel_warning_dates_coerced_na}}{Tier 1. Some dates could not
#'     be parsed and became `NA`.}
#'   \item{\code{creel_warning_design_length_disagrees}}{Tier 1. A design
#'     table's stored shift length disagrees with its clock window. See
#'     [fetch_design()].}
#'   \item{\code{creel_warning_numeric_coerced_na}}{Tier 1. Some values of a
#'     numeric column could not be read as numbers and became `NA`.}
#'   \item{\code{creel_warning_fetch_created_duplicates}}{Tier 1. The fetch
#'     made interview rows exact duplicates, so each copy counts that interview
#'     again: usually by dropping unmapped columns of a long-format source,
#'     sometimes by coercing or mapping values to the same value.}
#'   \item{\code{creel_warning_repeated_sampling_units}}{Tier 1. Counts have
#'     repeated dates with no count time to tell them apart.}
#'   \item{\code{creel_warning_tz_option_differs}}{Tier 1. A profile's `tz:`
#'     differs from the `tidycreel.tz` option already set, which is kept, so a
#'     night design given no `tz` is read in the option's zone, not the
#'     profile's. See [creel_connect_from_yaml()].}
#'   \item{\code{creel_warning_bins_without_count}}{Tier 1. Length bins were
#'     fetched without a fish count, so a distribution built from them is
#'     weighted by rows, not fish.}
#'   \item{\code{creel_warning_discovery_field_missing}}{Tier 2. The discovery
#'     response lacks an expected field, which is filled with `NA`.}
#'   \item{\code{creel_warning_odbc_drivers_unlisted}}{Tier 2.
#'     [creel_check_driver()] could not list the ODBC drivers.}
#' }
#'
#' @section Messages (tier 3):
#' \describe{
#'   \item{\code{creel_message_argument_ignored}}{Tier 3. An argument has no
#'     effect in this call: `schema` column mappings on the API backend.}
#'   \item{\code{creel_message_columns_by_canonical_name}}{Tier 3. Unmapped
#'     source columns were taken because they already carry a canonical name.
#'     Once per connection.}
#'   \item{\code{creel_message_columns_dropped}}{Tier 3. Source columns not
#'     mapped are not carried through. Once per connection.}
#'   \item{\code{creel_message_corrections_applied}}{Tier 3. A profile's
#'     corrections file changed fetched values; each change is listed. Once
#'     per connection. The result also carries them as
#'     `attr(x, "corrections")`. See [creel_connect_from_yaml()].}
#'   \item{\code{creel_message_rows_cleaned}}{Tier 3. A profile's
#'     `cleanup:` dropped placeholder rows or collapsed exact repeats; says how
#'     many of each. Once per connection. The result also carries the counts
#'     as `attr(x, "cleanup")`. See [creel_connect_from_yaml()].}
#'   \item{\code{creel_message_tz_option_set}}{Tier 3. A profile's `tz:` set
#'     the `tidycreel.tz` option, which was unset, for the session.}
#' }
#'
#' @name connect_warnings
NULL

# Tier of each class. A class raised in the code but missing here, or listed
# here but raised nowhere, fails tests/testthat/test-signal-classes.R.
connect_signal_tiers <- c(
  # Tier 1
  creel_warning_bins_without_count = 1L,
  creel_warning_dates_coerced_na = 1L,
  creel_warning_design_length_disagrees = 1L,
  creel_warning_fetch_created_duplicates = 1L,
  creel_warning_numeric_coerced_na = 1L,
  creel_warning_repeated_sampling_units = 1L,
  creel_warning_tz_option_differs = 1L,
  # Tier 2
  creel_warning_discovery_field_missing = 2L,
  creel_warning_odbc_drivers_unlisted = 2L,
  # Tier 3
  creel_message_argument_ignored = 3L,
  creel_message_columns_by_canonical_name = 3L,
  creel_message_columns_dropped = 3L,
  creel_message_corrections_applied = 3L,
  creel_message_rows_cleaned = 3L,
  creel_message_tz_option_set = 3L
)

# Notes about the source's shape. They are the same on every fetch of a table
# from one source, so repeating them buries the warnings that matter.
connect_once_per_connection <- c(
  "creel_message_columns_by_canonical_name",
  "creel_message_columns_dropped",
  "creel_message_corrections_applied",
  "creel_message_rows_cleaned"
)

#' Raise a tier-3 note as a classed message
#'
#' `class` is the note's own class; the parent `creel_message` is added. A
#' once-per-connection note prints the first time `key` is seen on `conn` and
#' is dropped after that. A first print a caller muffles still counts, as in
#' tidycreel. Without `conn` (or on a connection saved before connections kept
#' notes) it prints on every call.
#'
#' @keywords internal
#' @noRd
connect_inform <- function(message, class, conn = NULL, key = NULL,
                           .envir = parent.frame()) {
  notes <- if (is.list(conn)) conn[["notes"]]
  if (class %in% connect_once_per_connection && is.environment(notes)) {
    # Kept as a value, not a binding name: R caps names at 10,000 bytes, and a
    # wide source's dropped columns pass that, which aborted the fetch. The
    # separator is a control character no column name carries, so two keys
    # cannot paste to the same string.
    id <- paste(c(class, key), collapse = "\x1f")
    if (id %in% notes[["seen"]]) {
      return(invisible(NULL))
    }
    notes[["seen"]] <- c(notes[["seen"]], id)
    # Without this a reader cannot tell a silent second fetch from one that
    # dropped nothing.
    message <- c(message, "i" = "Shown once per connection for this table.")
  }
  cli::cli_inform(message, class = c(class, "creel_message"), .envir = .envir)
}
