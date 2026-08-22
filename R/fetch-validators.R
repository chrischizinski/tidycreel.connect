# Internal validation helpers for fetch_*() output data frames
# These are called after rename/coerce and before the tibble is returned.
# Each function collects ALL failures then issues a single cli_abort().

# Internal helper: check one column against expected type
# "optional" passes whether the column is absent or present, at any type.
# "optional:<type>" passes when absent, but enforces <type> when present -- an
# optional column that reaches a downstream calculation still has to be the right
# type there, and a character n_anglers would otherwise be accepted here and fail
# far away (GH #126).
# Returns character(0) on pass, a named "x" bullet on fail
.check_col <- function(df, col, expected_type, fn_name) {
  optional <- expected_type == "optional" || startsWith(expected_type, "optional:")
  if (!col %in% names(df)) {
    if (optional) return(character(0))
    return(stats::setNames(
      paste0(col, " (", expected_type, "): column missing"),
      "x"
    ))
  }
  if (startsWith(expected_type, "optional:")) {
    expected_type <- sub("^optional:", "", expected_type)
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
    trip_status   = "character",
    # Optional: carried only when mapped, but type-checked when carried.
    # n_anglers is the party size; site/circuit/n_counted/n_interviewed are the
    # bus-route expansion columns (GH #126).
    n_anglers     = "optional:numeric",
    angler_type   = "optional:character",
    site          = "optional:character",
    circuit       = "optional:character",
    n_counted     = "optional:numeric",
    n_interviewed = "optional:numeric"
  )
  .validate_fetch(df, spec, "fetch_interviews")
}

# API variant: catch_count is not required, because many APIs report catch on a
# separate endpoint rather than as a per-trip total on the interview. Users
# aggregate from fetch_catch() instead.
#' @noRd
#' @keywords internal
validate_fetch_interviews_api <- function(df) {
  spec <- list(
    interview_uid = "uid",
    date          = "Date",
    effort        = "numeric",
    trip_status   = "character",
    n_anglers     = "optional:numeric",
    angler_type   = "optional:character",
    site          = "optional:character",
    circuit       = "optional:character",
    n_counted     = "optional:numeric",
    n_interviewed = "optional:numeric"
  )
  .validate_fetch(df, spec, "fetch_interviews")
}


#' @noRd
#' @keywords internal
validate_fetch_counts <- function(df) {
  spec <- list(
    date          = "Date",
    bank_anglers  = "numeric",
    angler_boats  = "optional",  # absent where a source counts no boats; numeric when present
    non_ang_boats = "optional"   # absent where a source counts no boats; numeric when present
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
  spec <- .lengths_spec()
  .validate_fetch(df, spec, "fetch_harvest_lengths")
  .validate_has_a_length(df, "fetch_harvest_lengths")
}


#' @noRd
#' @keywords internal
validate_fetch_release_lengths <- function(df) {
  spec <- .lengths_spec()
  .validate_fetch(df, spec, "fetch_release_lengths")
  .validate_has_a_length(df, "fetch_release_lengths")
}

# Internal: the shared column contract for both lengths tables.
#
# `length_mm` is no longer unconditionally required: a source that reports
# binned release lengths has no per-fish measurement to give, and demanding one
# is what pushed a bin label into a column named `_mm` (GH #127). Exactly one of
# the two must arrive, which .validate_has_a_length() enforces.
.lengths_spec <- function() {
  list(
    length_uid    = "uid",
    interview_uid = "uid",
    species       = "character",
    length_mm     = "optional:numeric",
    length_bin    = "optional:character",
    count         = "optional:numeric",
    length_type   = "character"
  )
}

# Internal: a lengths table with neither a measurement nor a bin carries no
# length at all, which the per-column spec cannot say on its own.
.validate_has_a_length <- function(df, fn_name) {
  if (!any(c("length_mm", "length_bin") %in% names(df))) {
    cli::cli_abort(c(
      paste0(fn_name, "() validation failed:"),
      "x" = "neither {.field length_mm} nor {.field length_bin} is present.",
      "i" = paste0(
        "Map {.field length_mm_col} for measured fish, or {.field length_bin_col} ",
        "plus {.field length_count_col} for binned rows."
      )
    ))
  }
  invisible(df)
}
