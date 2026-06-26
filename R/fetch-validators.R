# Internal validation helpers for fetch_*() output data frames
# These are called after rename/coerce and before the tibble is returned.
# Each function collects ALL failures then issues a single cli_abort().

# Internal helper: check one column against expected type
# Returns character(0) on pass, a named "x" bullet on fail
.check_col <- function(df, col, expected_type, fn_name) {
  if (!col %in% names(df)) {
    if (expected_type == "optional") return(character(0))
    return(stats::setNames(
      paste0(col, " (", expected_type, "): column missing"),
      "x"
    ))
  }
  if (expected_type %in% c("any", "optional")) {
    return(character(0))
  }
  ok <- switch(expected_type,
    "Date"      = inherits(df[[col]], "Date"),
    "numeric"   = is.numeric(df[[col]]),
    "character" = is.character(df[[col]]),
    "uid"       = is.numeric(df[[col]]) || is.character(df[[col]]),
    stop(paste0("Unknown expected_type '", expected_type, "' for column '", col, "'"))
  )
  if (!ok) {
    actual <- paste(class(df[[col]]), collapse = "/")
    return(stats::setNames(
      paste0(col, " (", expected_type, "): found ", actual),
      "x"
    ))
  }
  character(0)
}

# Internal: validate df against a named list of col -> expected_type specs
.validate_fetch <- function(df, spec, fn_name) {
  bullets <- character(0)
  for (col in names(spec)) {
    bullets <- c(bullets, .check_col(df, col, spec[[col]], fn_name))
  }
  if (length(bullets) > 0L) {
    cli::cli_abort(c(
      paste0(fn_name, "() validation failed:"),
      bullets
    ))
  }
  invisible(df)
}


#' @noRd
#' @keywords internal
validate_fetch_interviews <- function(df) {
  spec <- list(
    interview_uid = "uid",
    date          = "Date",
    catch_count   = "numeric",
    effort        = "numeric",
    trip_status   = "character"
  )
  .validate_fetch(df, spec, "fetch_interviews")
}

# API variant: catch_count is absent from the AGENCY interviews endpoint (Num is in
# CatchRecords, not InterviewRecords). Users aggregate from fetch_catch() instead.
#' @noRd
#' @keywords internal
validate_fetch_interviews_api <- function(df) {
  spec <- list(
    interview_uid = "uid",
    date          = "Date",
    effort        = "numeric",
    trip_status   = "character"
  )
  .validate_fetch(df, spec, "fetch_interviews")
}


#' @noRd
#' @keywords internal
validate_fetch_counts <- function(df) {
  spec <- list(
    date          = "Date",
    bank_anglers  = "numeric",
    angler_boats  = "optional",  # absent for non-AGENCY backends; numeric when present
    non_ang_boats = "optional"   # absent for non-AGENCY backends; numeric when present
  )
  .validate_fetch(df, spec, "fetch_counts")
}


#' @noRd
#' @keywords internal
validate_fetch_catch <- function(df) {
  spec <- list(
    catch_uid     = "uid",
    interview_uid = "uid",
    species       = "character",
    catch_count   = "numeric",
    catch_type    = "character"
  )
  .validate_fetch(df, spec, "fetch_catch")
}


#' @noRd
#' @keywords internal
validate_fetch_harvest_lengths <- function(df) {
  spec <- list(
    length_uid    = "uid",
    interview_uid = "uid",
    species       = "character",
    length_mm     = "numeric",
    length_type   = "character"
  )
  .validate_fetch(df, spec, "fetch_harvest_lengths")
}


#' @noRd
#' @keywords internal
validate_fetch_release_lengths <- function(df) {
  spec <- list(
    length_uid    = "uid",
    interview_uid = "uid",
    species       = "character",
    length_mm     = "numeric",
    length_type   = "character"
  )
  .validate_fetch(df, spec, "fetch_release_lengths")
}
