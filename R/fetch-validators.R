# Internal validation helpers for fetch_*() output data frames
# These are called after rename/coerce and before the tibble is returned.
# Each function collects ALL failures then issues a single cli_abort().

# Internal helper: check one column against expected type
# Returns character(0) on pass, a named "x" bullet on fail
.check_col <- function(df, col, expected_type, fn_name) {
  if (!col %in% names(df)) {
    return(stats::setNames(
      paste0(col, " (", expected_type, "): column missing"),
      "x"
    ))
  }
  if (expected_type == "any") {
    return(character(0))
  }
  ok <- switch(expected_type,
    "Date"      = inherits(df[[col]], "Date"),
    "numeric"   = is.numeric(df[[col]]),
    "character" = is.character(df[[col]]),
    TRUE
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
    interview_uid = "any",
    date          = "Date",
    catch_count   = "numeric",
    effort        = "numeric",
    trip_status   = "character"
  )
  .validate_fetch(df, spec, "fetch_interviews")
}


#' @noRd
#' @keywords internal
validate_fetch_counts <- function(df) {
  spec <- list(
    date         = "Date",
    angler_count = "numeric"
  )
  .validate_fetch(df, spec, "fetch_counts")
}


#' @noRd
#' @keywords internal
validate_fetch_catch <- function(df) {
  spec <- list(
    catch_uid     = "any",
    interview_uid = "any",
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
    length_uid    = "any",
    interview_uid = "any",
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
    length_uid    = "any",
    interview_uid = "any",
    species       = "character",
    length_mm     = "numeric",
    length_type   = "character"
  )
  .validate_fetch(df, spec, "fetch_release_lengths")
}
