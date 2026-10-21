# The creel's own design tables (GH #4, part B).

#' Load a creel's design tables from an API connection
#'
#' @description
#' Many agency creel APIs serve the survey's own design alongside its data:
#' the season, the shift windows with their selection probabilities, the
#' sections and the special dates. `fetch_design()` reads them through the
#' same profile as the data, renames them to canonical columns and returns them
#' as a list, so a calendar can be built from what the design says rather than
#' recomputed by hand.
#'
#' Like every other endpoint, the design endpoints and their field names are
#' the caller's to declare: add `design_general`, `design_periods` and,
#' optionally, `design_sections` and `design_special_dates` to `endpoints` and
#' to `api_field_map` (or the profile's `endpoints:` and `field_map:`).
#'
#' # Shift lengths
#'
#' Each period's length is computed from its start and end clock times, adding
#' a day when the end is not after the start: a shift that crosses midnight.
#' The length the source stores is kept beside it as `stored_length_hours`,
#' and every period where the two disagree is reported with a warning
#' (`creel_warning_design_length_disagrees`) rather than one silently preferred.
#' A stored length computed as end - start on a clock that wraps (a 19:30-00:30
#' shift stored as -19 h) has reached published reports; this is the check
#' that catches it. `crosses_midnight` marks the shifts that make a night
#' design (see [tidycreel::creel_design()]).
#'
#' These are the **real** shift lengths. tidycreel divides by `p_period`
#' itself, so a length already divided by the probability must never be passed
#' to [tidycreel::add_counts()].
#'
#' @param conn A `creel_connection` created by [creel_connect_api()] or
#'   [creel_connect_from_yaml()].
#' @param ... Reserved for future arguments.
#'
#' @return A named list of data frames, each with `creel_uid`, the creel UID it
#'   was fetched for:
#'   - `general`: one row per creel. `season_start`, `season_end` (Date), and
#'     the special-date rule as two logical flags: `special_as_stratum`
#'     (special dates form strata of their own) and `special_as_weekend`
#'     (special dates join the weekend), each carried when mapped.
#'   - `periods`: one row per month and period. `month` (integer),
#'     `period_id` (character), `start_time`, `end_time` (character,
#'     `"HH:MM"`), `length_hours` (numeric, from the clock times),
#'     `crosses_midnight` (logical), `p_period` (numeric, in (0, 1]), and
#'     `stored_length_hours` when the source stores one.
#'   - `sections`: `section` (character), or `NULL` when no
#'     `design_sections` endpoint is configured.
#'   - `special_dates`: `date` (Date) and `group` (character, when mapped), or
#'     `NULL` when no `design_special_dates` endpoint is configured.
#' @export
fetch_design <- function(conn, ...) UseMethod("fetch_design")

#' @export
fetch_design.creel_connection <- function(conn, ...) {
  cli::cli_abort(c(
    "{.fn fetch_design} reads design tables from an API connection.",
    "x" = "This connection's backend is {.val {conn$backend}}."
  ))
}

#' @export
fetch_design.creel_connection_api <- function(conn, ...) {
  list(
    general       = .fetch_design_general(conn),
    periods       = .fetch_design_periods(conn),
    sections      = .fetch_design_optional(conn, "design_sections", .design_sections),
    special_dates = .fetch_design_optional(conn, "design_special_dates", .design_special_dates)
  )
}

# Internal: fetch one design endpoint and rename it. The canonical columns
# each table may carry are listed by its caller; c() drops unnamed ones.
.fetch_design_table <- function(conn, endpoint, canonical) {
  raw_df <- .api_fetch(conn$con, endpoint)
  fm <- conn$con$api_field_map[[endpoint]]
  map <- unlist(fm[intersect(canonical, names(fm))])
  map <- c(creel_uid = ".creel_uid", map[!is.na(map) & nzchar(map)])
  .rename_api_to_canonical(raw_df, map, endpoint, conn = conn)
}

.fetch_design_optional <- function(conn, endpoint, build) {
  if (is.null(conn$con$endpoints[[endpoint]])) {
    return(NULL)
  }
  build(conn)
}

.fetch_design_general <- function(conn) {
  df <- .fetch_design_table(
    conn, "design_general",
    c("season_start", "season_end", "special_as_stratum", "special_as_weekend")
  )
  .require_design_cols(df, c("season_start", "season_end"), "design_general")
  .require_every_creel(df, conn, "design_general")
  df$season_start <- .parse_api_date(df$season_start, "season_start")
  df$season_end <- .parse_api_date(df$season_end, "season_end")
  # A season with no start or end has no days to build a calendar from.
  if (anyNA(df$season_start) || anyNA(df$season_end)) {
    cli::cli_abort("design_general: the season start or end is missing or unreadable.")
  }
  for (nm in c("special_as_stratum", "special_as_weekend")) {
    if (nm %in% names(df)) df[[nm]] <- .coerce_flag(df[[nm]], "design_general", nm)
  }
  df
}

.fetch_design_periods <- function(conn) {
  df <- .fetch_design_table(
    conn, "design_periods",
    c("month", "period_id", "start_time", "end_time", "stored_length_hours", "p_period")
  )
  .require_design_cols(
    df, c("month", "period_id", "start_time", "end_time", "p_period"), "design_periods"
  )
  .require_every_creel(df, conn, "design_periods")
  df$month <- as.integer(.coerce_numeric(df$month, "month"))
  df$period_id <- as.character(df$period_id)
  df$p_period <- .coerce_numeric(df$p_period, "p_period")
  # Missing is refused with out-of-range: tidycreel divides by it.
  bad_p <- is.na(df$p_period) | df$p_period <= 0 | df$p_period > 1
  if (any(bad_p)) {
    cli::cli_abort(c(
      "design_periods: {.field p_period} is missing or outside (0, 1] on {sum(bad_p)} row{?s}.",
      "i" = "It is the probability that the period is the one worked on a sampled day."
    ))
  }
  start <- .clock_minutes(df$start_time, "start_time")
  end <- .clock_minutes(df$end_time, "end_time")
  df$start_time <- .format_clock(start)
  df$end_time <- .format_clock(end)
  df$crosses_midnight <- end <= start
  df$length_hours <- (end - start + ifelse(df$crosses_midnight, 1440, 0)) / 60
  if ("stored_length_hours" %in% names(df)) {
    df$stored_length_hours <- .coerce_numeric(df$stored_length_hours, "stored_length_hours")
    .warn_design_length_disagrees(df)
  }
  df
}

.design_sections <- function(conn) {
  df <- .fetch_design_table(conn, "design_sections", "section")
  if (nrow(df) == 0L) {
    return(data.frame(creel_uid = character(0), section = character(0)))
  }
  .require_design_cols(df, "section", "design_sections")
  df$section <- as.character(df$section)
  df
}

.design_special_dates <- function(conn) {
  df <- .fetch_design_table(conn, "design_special_dates", c("date", "group"))
  # Most seasons have none.
  if (nrow(df) == 0L) {
    empty <- data.frame(creel_uid = character(0), date = as.Date(character(0)))
    # Same shape as a season with special dates: a mapped group stays.
    if (.field_named(conn$con$api_field_map$design_special_dates$group)) {
      empty$group <- character(0)
    }
    return(empty)
  }
  .require_design_cols(df, "date", "design_special_dates")
  df$date <- .parse_api_date(df$date)
  if ("group" %in% names(df)) df$group <- as.character(df$group)
  df
}

# Internal: a required design column missing after the rename is a field-map
# problem; say which field to name rather than fail later on a NULL column.
# The season and the periods are the design; a creel with neither cannot be
# built into a calendar, so an empty response for them is refused.
.require_design_cols <- function(df, cols, endpoint) {
  if (nrow(df) == 0L) {
    cli::cli_abort(c(
      "{endpoint}: the API returned no rows.",
      "i" = "Check the creel UID{?s} and the {.field {endpoint}} endpoint."
    ))
  }
  missing_cols <- setdiff(cols, names(df))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "{endpoint}: required field{?s} {.field {missing_cols}} not found.",
      "i" = "Name the raw field for each in {.arg api_field_map}${endpoint}."
    ))
  }
  invisible(NULL)
}

# Internal: every requested creel must have rows in a required design table.
# Empty blocks are dropped when creels are bound, so a creel with no season
# would otherwise vanish from `general` while its periods remain.
.require_every_creel <- function(df, conn, endpoint) {
  absent <- setdiff(conn$con$creel_uids, df$creel_uid)
  if (length(absent) > 0L) {
    cli::cli_abort(c(
      "{endpoint}: the API returned no rows for creel{?s} {.val {absent}}.",
      "i" = "A creel with no design cannot be built into a calendar."
    ))
  }
  invisible(NULL)
}

# Internal: minutes after midnight from a clock time in any of the shapes an
# API sends one -- "19:30", "19:30:00", "1900-01-01T19:30:00" -- taking the
# first HH:MM. Unreadable values abort: a shift with no window has no length.
.clock_minutes <- function(x, field) {
  x <- trimws(as.character(x))
  # The whole value must be a time, optionally after a date and with seconds
  # or a zone: matching anywhere inside it read 25:10:00 as 10:00.
  pattern <- paste0(
    "^(\\d{4}-\\d{2}-\\d{2}[T ])?([01]?[0-9]|2[0-3]):([0-5][0-9])",
    "(:[0-5][0-9](\\.[0-9]+)?)?(Z|[+-][0-9]{2}:?[0-9]{2})?$"
  )
  ok <- !is.na(x) & grepl(pattern, x, perl = TRUE)
  if (!all(ok)) {
    cli::cli_abort(c(
      "design_periods: {.field {field}} is not a clock time on {sum(!ok)} row{?s}.",
      "i" = "Expected a time such as 19:30, 19:30:00 or 1900-01-01T19:30:00; a missing time has no length."
    ))
  }
  hh <- as.integer(sub(pattern, "\\2", x, perl = TRUE))
  mm <- as.integer(sub(pattern, "\\3", x, perl = TRUE))
  hh * 60L + mm
}

.format_clock <- function(minutes) sprintf("%02d:%02d", minutes %/% 60L, minutes %% 60L)

# Internal: a yes/no flag from the shapes a design table uses.
.coerce_flag <- function(x, endpoint, field) {
  if (is.logical(x)) {
    return(x)
  }
  values <- tolower(trimws(as.character(x)))
  out <- rep(NA, length(values))
  out[values %in% c("true", "t", "yes", "y", "1")] <- TRUE
  out[values %in% c("false", "f", "no", "n", "0")] <- FALSE
  if (any(!is.na(values) & nzchar(values) & is.na(out))) {
    cli::cli_abort(
      "{endpoint}: {.field {field}} holds values that are not a yes/no flag."
    )
  }
  out
}

# Internal: report every period whose stored length disagrees with its clock
# window. Both values stay in the table; the computed one is `length_hours`.
.warn_design_length_disagrees <- function(df) {
  off <- !is.na(df$stored_length_hours) &
    abs(df$stored_length_hours - df$length_hours) > 0.01
  if (!any(off)) {
    return(invisible(NULL))
  }
  rows <- sprintf(
    "month %s, period %s (%s-%s): stored %s h, window %s h",
    df$month[off], df$period_id[off], df$start_time[off], df$end_time[off],
    format(df$stored_length_hours[off]), format(df$length_hours[off])
  )
  if ("creel_uid" %in% names(df)) rows <- paste0(df$creel_uid[off], " ", rows)
  cli::cli_warn(
    c(
      "design_periods: the stored shift length disagrees with the clock window on \\
       {sum(off)} period{?s}.",
      stats::setNames(gsub("([{}])", "\\1\\1", rows), rep("*", sum(off))),
      "i" = "{.field length_hours} is computed from the window; the source's value is \\
             kept as {.field stored_length_hours}. A negative stored length is a \\
             window that crosses midnight computed as end - start."
    ),
    class = c("creel_warning_design_length_disagrees", "creel_warning")
  )
  invisible(NULL)
}
