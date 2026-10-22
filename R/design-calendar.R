# The design calendar built from a creel's design tables and counts (GH #4,
# part C).

#' Build a design calendar from a creel's design tables and counts
#'
#' @description
#' `design_calendar()` turns the tables [fetch_design()] returns, and the
#' counts that say which days were worked, into the calendar
#' [tidycreel::creel_design()] takes: every day of the season with its
#' stratum and, on each worked day, the shift drawn, its window, its real
#' length and its selection probability.
#'
#' The design tables say what *could* be drawn: the shift windows and their
#' probabilities by month. Which days were sampled, and which shift was drawn
#' on each, only the counts say: a day with counts is a worked day, and the
#' counts' `period_col` names the shift worked.
#'
#' # Strata
#'
#' Ordinary days are stratified by month x day type (`weekday`, `weekend`).
#' Special dates follow the rule in `special_dates`:
#' - `"stratum"`: each special-date group is a stratum of its own, not split
#'   by month, with day type `special`;
#' - `"weekend"`: special dates join the weekend of their month;
#' - `"ignore"`: special dates are ordinary days.
#'
#' Left `NULL`, the rule is the design's own: the `special_as_stratum` and
#' `special_as_weekend` flags of the general table, named in the profile's
#' `field_map:`. A design with special dates and neither flag is refused
#' rather than guessed.
#'
#' # Shifts
#'
#' `shift_hours` is the **real** length of the drawn shift and `p_period` its
#' probability, kept apart: tidycreel divides by `p_period` itself, so pass
#' `shift_hours` to [tidycreel::add_counts()] as it is. A length already
#' divided by the probability would apply it twice.
#'
#' A day with counts in more than one shift has no single probability and is
#' refused (`creel_error_calendar_two_shifts`), with the days listed: a day
#' worked off-design is fixed in the
#' profile's corrections file, not guessed. So is a count with no shift, a
#' shift the month's design does not have, and a count outside the season.
#'
#' # Night designs
#'
#' When a shift crosses midnight the design is a night design, and the
#' calendar carries `day_start`, the clock time at which each survey day
#' begins (see [tidycreel::creel_design()]). It defaults to the earliest shift
#' start in the design; every shift must fit inside one survey day. The time
#' zone is the profile's `tz:`.
#'
#' A night is labelled by the date it began, and a count's `date` and
#' `count_time` are when it was made, as tidycreel reads them: a count before
#' `day_start` belongs to the night before, so a 00:15 count dated 1 July
#' works the night of 30 June. A night design therefore needs each count's
#' `count_time` as a clock time (`"HH:MM"`).
#'
#' Sections are not used: the calendar is per day.
#'
#' @param design The list returned by [fetch_design()].
#' @param counts Counts for the same creel, as returned by [fetch_counts()]:
#'   a `date` column and the drawn shift in `period_col`.
#' @param period_col Name of the counts column holding the shift drawn on
#'   each day, matched to the design's `period_id`. Usually carried through
#'   the profile's `strata_cols:`.
#' @param creel_uid The creel to build the calendar for. Required when
#'   `design` holds more than one; counts with a `creel_uid` column are
#'   filtered to it.
#' @param special_dates The special-date rule: `"stratum"`, `"weekend"` or
#'   `"ignore"`, or `NULL` to take it from the design.
#' @param day_start For a night design, the clock time (`"HH:MM"`) at which
#'   a survey day begins, or `NULL` for the earliest shift start. Ignored for
#'   a design with no shift crossing midnight.
#'
#' @return A data frame with one row per day of the season: `date`, `month`
#'   (integer), `day_type`, `stratum`, and the drawn shift on worked days
#'   (`NA` on the others): `period_id`, `p_period`, `shift_start`,
#'   `shift_end` (`"HH:MM"`) and `shift_hours`. A night design adds
#'   `day_start`.
#' @export
design_calendar <- function(design, counts, period_col = "period",
                            creel_uid = NULL, special_dates = NULL,
                            day_start = NULL) {
  if (!is.list(design) || !all(c("general", "periods") %in% names(design))) {
    cli::cli_abort("{.arg design} must be the list returned by {.fn fetch_design}.")
  }
  if (!is.null(special_dates)) {
    special_dates <- rlang::arg_match(special_dates, c("stratum", "weekend", "ignore"))
  }
  uid <- .calendar_creel_uid(design$general, creel_uid)
  general <- design$general[design$general$creel_uid == uid, , drop = FALSE]
  if (nrow(general) != 1L) {
    cli::cli_abort("design$general: expected one season for creel {.val {uid}}, found {nrow(general)}.")
  }
  periods <- design$periods[design$periods$creel_uid == uid, , drop = FALSE]
  special <- design$special_dates
  if (!is.null(special)) special <- special[special$creel_uid == uid, , drop = FALSE]

  cal <- .calendar_days(general, special, special_dates)
  night <- any(periods$crosses_midnight)
  if (night) day_start <- .calendar_day_start(periods, day_start)
  worked <- .calendar_worked_shifts(
    counts, period_col, uid, periods, cal$date,
    day_start = if (night) day_start
  )

  i <- match(cal$date, worked$date)
  cal$period_id <- worked$period_id[i]
  cal$p_period <- worked$p_period[i]
  cal$shift_start <- worked$start_time[i]
  cal$shift_end <- worked$end_time[i]
  cal$shift_hours <- worked$length_hours[i]
  if (night) cal$day_start <- day_start
  cal
}

# Internal: the creel the calendar is for. One creel in the design needs no
# argument; several do, because a calendar is one creel's season.
.calendar_creel_uid <- function(general, creel_uid) {
  uids <- unique(general$creel_uid)
  if (is.null(creel_uid)) {
    if (length(uids) != 1L) {
      cli::cli_abort(c(
        "{.arg design} holds {length(uids)} creels: {.val {uids}}.",
        "i" = "Name the one to build a calendar for with {.arg creel_uid}."
      ))
    }
    return(uids)
  }
  if (!is.character(creel_uid) || length(creel_uid) != 1L || !creel_uid %in% uids) {
    cli::cli_abort("{.arg creel_uid} must be one of the design's creels: {.val {uids}}.")
  }
  creel_uid
}

# Internal: every day of the season with its day type and stratum.
.calendar_days <- function(general, special, rule) {
  date <- seq(general$season_start, general$season_end, by = "day")
  month <- as.integer(format(date, "%m"))
  day_type <- ifelse(format(date, "%u") %in% c("6", "7"), "weekend", "weekday")
  cal <- data.frame(date = date, month = month, day_type = day_type)
  cal$stratum <- sprintf("%02d_%s", cal$month, cal$day_type)
  if (is.null(special) || nrow(special) == 0L) {
    return(cal)
  }
  if (is.null(rule)) rule <- .calendar_special_rule(general)
  if (rule == "ignore") {
    return(cal)
  }
  i <- match(unique(special$date), cal$date)
  if (anyNA(i)) {
    outside <- unique(special$date)[is.na(i)] # nolint: object_usage_linter
    cli::cli_abort(
      "design$special_dates: {length(outside)} special date{?s} outside the season: {.val {format(outside)}}."
    )
  }
  if (rule == "weekend") {
    cal$day_type[i] <- "weekend"
    cal$stratum[i] <- sprintf("%02d_weekend", cal$month[i])
    return(cal)
  }
  # rule == "stratum": each group is its own stratum, across months.
  if (!"group" %in% names(special) || anyNA(special$group)) {
    cli::cli_abort(c(
      "design$special_dates: special dates form strata of their own, but some have no {.field group}.",
      "i" = "Map {.field group} in the profile's {.field design_special_dates} field map."
    ))
  }
  group <- special$group[match(cal$date[i], special$date)]
  cal$day_type[i] <- "special"
  cal$stratum[i] <- paste0("special_", group)
  cal
}

# Internal: the special-date rule the design itself states.
.calendar_special_rule <- function(general) {
  flag <- function(nm) if (nm %in% names(general)) general[[nm]] else NA
  as_stratum <- flag("special_as_stratum")
  as_weekend <- flag("special_as_weekend")
  if (isTRUE(as_stratum) && isTRUE(as_weekend)) {
    cli::cli_abort(c(
      "design$general: special dates are both a stratum of their own and part of the weekend.",
      "i" = "Choose one with {.arg special_dates}."
    ))
  }
  if (isTRUE(as_stratum)) {
    return("stratum")
  }
  if (isTRUE(as_weekend)) {
    return("weekend")
  }
  if (isFALSE(as_stratum) && isFALSE(as_weekend)) {
    return("ignore")
  }
  cli::cli_abort(c(
    "The design has special dates but does not say how they are stratified.",
    "i" = "Map {.field special_as_stratum} and {.field special_as_weekend} in the \\
           profile's {.field design_general} field map, or set {.arg special_dates}."
  ))
}

# Internal: when a survey day begins on a night design. Every shift must
# start at or after it and end by the next one, or its counts would fall on
# two survey days.
.calendar_day_start <- function(periods, day_start) {
  if (is.null(day_start)) {
    ds <- min(.clock_minutes(periods$start_time, "start_time")) # nolint: object_usage_linter
  } else {
    ok <- is.character(day_start) && length(day_start) == 1L &&
      grepl("^([01][0-9]|2[0-3]):[0-5][0-9]$", day_start)
    if (!ok) cli::cli_abort("{.arg day_start} must be one clock time such as {.val 12:00}.")
    ds <- .clock_minutes(day_start, "day_start") # nolint: object_usage_linter
  }
  start <- (.clock_minutes(periods$start_time, "start_time") - ds) %% 1440L # nolint: object_usage_linter
  end <- (.clock_minutes(periods$end_time, "end_time") - ds) %% 1440L # nolint: object_usage_linter
  end[end == 0L] <- 1440L
  leaves <- end <= start
  if (any(leaves)) {
    rows <- sprintf(
      "month %s, period %s (%s-%s)", periods$month[leaves], periods$period_id[leaves],
      periods$start_time[leaves], periods$end_time[leaves]
    )
    ds_clock <- .format_clock(ds) # nolint: object_usage_linter
    cli::cli_abort(c(
      "A shift does not fit inside one survey day starting at {.val {ds_clock}}.",
      stats::setNames(gsub("([{}])", "\\1\\1", rows), rep("*", length(rows))),
      "i" = "Set {.arg day_start} to a time no shift spans."
    ))
  }
  .format_clock(ds) # nolint: object_usage_linter
}

# Internal: the survey day of each count on a night design. As in tidycreel,
# a count's date and time are when it was made, and a night is labelled by
# the date it began, so a count before `day_start` belongs to the survey day
# before: a 00:15 count dated 1 July is the night of 30 June.
.calendar_survey_day <- function(counts, day_start) {
  ct <- if ("count_time" %in% names(counts)) trimws(as.character(counts$count_time))
  ok <- !is.null(ct) && all(grepl("^([01]?[0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$", ct))
  if (!ok) {
    cli::cli_abort(c(
      "{.arg counts}: a night design needs each count's {.field count_time} as a clock time.",
      "i" = "A count after midnight belongs to the night before, which only its time says."
    ))
  }
  minutes <- as.integer(sub(":.*", "", ct)) * 60L + as.integer(sub("^[0-9]+:([0-9]+).*", "\\1", ct))
  counts$date - as.numeric(minutes < .clock_minutes(day_start, "day_start")) # nolint: object_usage_linter
}

# Internal: the shift worked on each sampled day, read from the counts and
# looked up in the month's periods.
.calendar_worked_shifts <- function(counts, period_col, uid, periods, season,
                                    day_start = NULL) {
  if (!is.data.frame(counts) || !"date" %in% names(counts) ||
        !inherits(counts$date, "Date")) {
    cli::cli_abort("{.arg counts} must be the data frame {.fn fetch_counts} returns, with a {.cls Date} {.field date}.")
  }
  if (!is.character(period_col) || length(period_col) != 1L || !period_col %in% names(counts)) {
    cli::cli_abort(c(
      "{.arg counts} has no {.field {period_col}} column naming the shift worked.",
      "i" = "Carry it through the profile's {.field strata_cols:}, or name it with {.arg period_col}."
    ))
  }
  if ("creel_uid" %in% names(counts)) counts <- counts[counts$creel_uid %in% uid, , drop = FALSE]
  date <- counts$date
  if (!is.null(day_start)) date <- .calendar_survey_day(counts, day_start)
  days <- unique(data.frame(date = date, period_id = as.character(counts[[period_col]])))

  no_date <- is.na(days$date)
  if (any(no_date)) {
    cli::cli_abort("{.arg counts}: {sum(no_date)} count{?s} {?has/have} no date.")
  }
  outside <- unique(days$date[!days$date %in% season])
  if (length(outside) > 0L) {
    cli::cli_abort(
      "{.arg counts}: {length(outside)} day{?s} with counts outside the season: {.val {format(outside)}}."
    )
  }
  no_shift <- unique(days$date[is.na(days$period_id)])
  if (length(no_shift) > 0L) {
    cli::cli_abort(c(
      "{.arg counts}: {length(no_shift)} day{?s} with counts that name no shift: {.val {format(no_shift)}}.",
      "i" = "Record the shift worked in the profile's corrections file."
    ))
  }
  two <- unique(days$date[duplicated(days$date)])
  if (length(two) > 0L) {
    cli::cli_abort(
      c(
        "{.arg counts}: {length(two)} day{?s} with counts in more than one shift: {.val {format(two)}}.",
        "x" = "One shift is drawn per sampled day, so such a day has no single {.field p_period}.",
        "i" = "Fix the shift recorded on those days in the profile's corrections file."
      ),
      class = "creel_error_calendar_two_shifts"
    )
  }

  key <- paste(as.integer(format(days$date, "%m")), days$period_id)
  i <- match(key, paste(periods$month, periods$period_id))
  if (anyNA(i)) {
    rows <- sprintf("%s: period %s", format(days$date[is.na(i)]), days$period_id[is.na(i)])
    cli::cli_abort(c(
      "{.arg counts}: {sum(is.na(i))} day{?s} worked a shift the month's design does not have.",
      stats::setNames(gsub("([{}])", "\\1\\1", rows), rep("*", length(rows))),
      "i" = "Check {.arg period_col} against the design's {.field period_id}."
    ))
  }
  cbind(
    days["date"],
    periods[i, c("period_id", "p_period", "start_time", "end_time", "length_hours")],
    row.names = NULL
  )
}
