# tidycreel.connect: fetch_*() generics, CSV methods, and SQL Server stubs
# Phase 68: FETCH-01 through FETCH-06, BACKEND-01, BACKEND-04

# Internal: load CSV with native BOM stripping (no locale argument needed)
.read_csv_safe <- function(path) {
  readr::read_csv(path, show_col_types = FALSE, progress = FALSE)
}

# Internal: as.numeric() that warns when coercion introduces NAs
.coerce_numeric <- function(x, col_name) {
  result <- suppressWarnings(as.numeric(x))
  na_new <- is.na(result) & !is.na(x)
  if (any(na_new)) {
    cli::cli_warn("Coercion introduced {sum(na_new)} NA{?s} in column {.field {col_name}}.")
  }
  result
}

# Internal: as.Date() that warns when parsing introduces NAs
.coerce_date <- function(x, col_name, formats = c("%Y-%m-%d", "%m/%d/%Y")) {
  result <- suppressWarnings(as.Date(x, tryFormats = formats))
  na_new <- is.na(result) & !is.na(x)
  if (any(na_new)) {
    cli::cli_warn(
      "Could not parse {sum(na_new)} date value{?s} in column {.field {col_name}}; coerced to NA."
    )
  }
  result
}

# Internal: rename raw AGENCY API columns to canonical names using a hardcoded map.
# api_rename_map: named character vector where names = canonical names,
#   values = raw AGENCY JSON field names (e.g., c(interview_uid = "api_UID", date = "api_Date")).
# Columns in api_rename_map but absent from df are silently dropped.
# Returns a plain data.frame with only matched canonical columns.
.rename_api_to_canonical <- function(df, api_rename_map) {
  keep <- character(0)
  for (canonical in names(api_rename_map)) {
    api_col <- api_rename_map[[canonical]]
    if (api_col %in% names(df)) {
      keep[[canonical]] <- api_col
    }
  }
  result <- df[, keep, drop = FALSE]
  names(result) <- names(keep)
  result
}

# Internal: rename CSV columns to canonical names using schema field mapping.
# rename_map: named character vector where names = canonical names,
#   values = schema field names (e.g., c(date = "date_col", ...)).
# Columns not found in the data frame are silently dropped (optional mapping).
# Returns a plain data.frame with only canonical columns.
.rename_to_canonical <- function(df, schema, rename_map) {
  keep <- character(0)
  for (canonical in names(rename_map)) {
    field <- rename_map[[canonical]]
    csv_col <- schema[[field]]
    if (!is.null(csv_col) && csv_col %in% names(df)) {
      keep[[canonical]] <- csv_col
    }
  }
  result <- df[, keep, drop = FALSE]
  names(result) <- names(keep)
  result
}


#' Load interview data from a creel connection
#'
#' @description
#' Reads the interviews table from a creel data source, renames columns to
#' canonical tidycreel names, coerces types, validates, and returns a
#' data frame ready for [tidycreel::add_interviews()].
#'
#' @param conn A `creel_connection` object created by [creel_connect()].
#' @param ... Reserved for future arguments.
#'
#' @return A data frame with canonical columns: `interview_uid`, `date`
#'   (Date), `catch_count` (numeric), `effort` (numeric),
#'   `trip_status` (character). Extra CSV columns are dropped.
#' @export
fetch_interviews <- function(conn, ...) UseMethod("fetch_interviews")

#' @export
fetch_interviews.creel_connection_csv <- function(conn, ...) {
  df <- .read_csv_safe(conn$con$interviews)
  rename_map <- c(
    interview_uid = "interview_uid_col",
    date          = "date_col",
    catch_count   = "catch_col",
    effort        = "effort_col",
    trip_status   = "trip_status_col"
  )
  df <- .rename_to_canonical(df, conn$schema, rename_map)
  if ("date"        %in% names(df)) df$date        <- .coerce_date(df$date, "date")
  if ("catch_count" %in% names(df)) df$catch_count <- .coerce_numeric(df$catch_count, "catch_count")
  if ("effort"      %in% names(df)) df$effort      <- .coerce_numeric(df$effort, "effort")
  if ("trip_status" %in% names(df)) df$trip_status <- as.character(df$trip_status)
  validate_fetch_interviews(df) # nolint: object_usage_linter
  df
}

#' @export
fetch_interviews.creel_connection_sqlserver <- function(conn, ...) {
  cli::cli_abort("SQL Server fetch_interviews() not yet implemented (Phase 69).")
}

#' @export
fetch_interviews.creel_connection_api <- function(conn, ...) {
  raw_df <- .api_fetch(conn$con, "interviews")

  # Early return for empty API response -- avoids logical-typed columns failing validation
  if (nrow(raw_df) == 0L) {
    return(data.frame(
      interview_uid    = character(0),
      date             = as.Date(character(0)),
      effort           = numeric(0),
      trip_status      = character(0),
      stringsAsFactors = FALSE
    ))
  }

  fm <- conn$con$api_field_map$interviews
  # catch_count: NULL in AGENCY defaults (Num lives in CatchRecords, not InterviewRecords);
  # non-NULL when caller supplies a custom api_field_map for a non-AGENCY API.
  # c() drops NULL entries silently, so the field is simply absent for AGENCY connections.
  api_rename_map <- c(
    interview_uid = fm$interview_uid,
    date          = fm$date,
    catch_count   = fm$catch_count,
    trip_status   = fm$trip_status
  )
  api_rename_map <- api_rename_map[!is.na(api_rename_map) & nzchar(api_rename_map)]
  df <- .rename_api_to_canonical(raw_df, api_rename_map)

  # Effort: arithmetic from two raw fields (API-01); or single field when effort_minutes is NULL
  hours_col   <- fm$effort_hours
  minutes_col <- fm$effort_minutes
  if (!is.null(hours_col) && nzchar(hours_col) && hours_col %in% names(raw_df)) {
    df$effort <- .coerce_numeric(raw_df[[hours_col]], hours_col)
    if (!is.null(minutes_col) && nzchar(minutes_col) && minutes_col %in% names(raw_df)) {
      df$effort <- df$effort + .coerce_numeric(raw_df[[minutes_col]], minutes_col) / 60
    }
  }

  if ("date"        %in% names(df)) df$date        <- .parse_api_date(df$date)
  if ("catch_count" %in% names(df)) df$catch_count <- .coerce_numeric(df$catch_count, "catch_count")
  if ("trip_status" %in% names(df)) df$trip_status <- as.character(df$trip_status)

  validate_fetch_interviews_api(df) # nolint: object_usage_linter
  df
}


#' Load count data from a creel connection
#'
#' @description
#' Reads the counts table from a creel data source, renames columns to
#' canonical tidycreel names, coerces types, validates, and returns a
#' data frame ready for [tidycreel::add_counts()].
#'
#' The result carries up to three numeric count columns, so
#' [tidycreel::add_counts()] cannot infer which one to expand into effort and
#' will abort unless you name it:
#'
#' ```r
#' counts <- fetch_counts(conn)
#' design <- tidycreel::add_counts(design, counts, count_col = bank_anglers)
#' ```
#'
#' `bank_anglers` counts anglers on shore; `angler_boats` and `non_ang_boats`
#' count boats, not anglers. Converting boats to anglers needs a mean party
#' size from the interviews, so summing the three columns is not a total angler
#' count -- build the column you want before calling `add_counts()`.
#'
#' @param conn A `creel_connection` object created by [creel_connect()].
#' @param ... Reserved for future arguments.
#'
#' @return A data frame with canonical columns: `date` (Date),
#'   `bank_anglers` (numeric), `angler_boats` (numeric), `non_ang_boats`
#'   (numeric). Extra CSV columns are dropped.
#' @export
fetch_counts <- function(conn, ...) UseMethod("fetch_counts")

#' @export
fetch_counts.creel_connection_csv <- function(conn, ...) {
  df <- .read_csv_safe(conn$con$counts)
  rename_map <- c(
    date          = "date_col",
    bank_anglers  = "bank_anglers_col",
    angler_boats  = "angler_boats_col",
    non_ang_boats = "non_ang_boats_col"
  )
  df <- .rename_to_canonical(df, conn$schema, rename_map)
  if ("date"          %in% names(df)) df$date          <- .coerce_date(df$date, "date")
  if ("bank_anglers"  %in% names(df)) df$bank_anglers  <- .coerce_numeric(df$bank_anglers, "bank_anglers")
  if ("angler_boats"  %in% names(df)) df$angler_boats  <- .coerce_numeric(df$angler_boats, "angler_boats")
  if ("non_ang_boats" %in% names(df)) df$non_ang_boats <- .coerce_numeric(df$non_ang_boats, "non_ang_boats")
  validate_fetch_counts(df) # nolint: object_usage_linter
  df
}

#' @export
fetch_counts.creel_connection_sqlserver <- function(conn, ...) {
  cli::cli_abort("SQL Server fetch_counts() not yet implemented (Phase 69).")
}

#' @export
fetch_counts.creel_connection_api <- function(conn, ...) {
  raw_df <- .api_fetch(conn$con, "counts")

  # Early return for empty API response
  if (nrow(raw_df) == 0L) {
    return(data.frame(
      date             = as.Date(character(0)),
      bank_anglers     = numeric(0),
      angler_boats     = numeric(0),
      non_ang_boats    = numeric(0),
      stringsAsFactors = FALSE
    ))
  }

  fm <- conn$con$api_field_map$counts
  # bank_anglers = anglers on shore; angler_boats = boats with anglers; non_ang_boats = boats without anglers
  # boat angler count derived from angler_boats * mean(anglers/boat) from interviews -- not a raw field
  api_rename_map <- c(
    date          = fm$date,
    bank_anglers  = fm$bank_anglers,
    angler_boats  = fm$angler_boats,
    non_ang_boats = fm$non_ang_boats
  )
  api_rename_map <- api_rename_map[!is.na(api_rename_map) & nzchar(api_rename_map)]
  df <- .rename_api_to_canonical(raw_df, api_rename_map)

  if ("date"          %in% names(df)) df$date          <- .parse_api_date(df$date)
  if ("bank_anglers"  %in% names(df)) df$bank_anglers  <- .coerce_numeric(df$bank_anglers, "bank_anglers")
  if ("angler_boats"  %in% names(df)) df$angler_boats  <- .coerce_numeric(df$angler_boats, "angler_boats")
  if ("non_ang_boats" %in% names(df)) df$non_ang_boats <- .coerce_numeric(df$non_ang_boats, "non_ang_boats")

  validate_fetch_counts(df) # nolint: object_usage_linter
  df
}


#' Load catch data from a creel connection
#'
#' @description
#' Reads the catch table from a creel data source, renames columns to
#' canonical tidycreel names, coerces types (including species to character),
#' validates, and returns a data frame ready for [tidycreel::add_catch()].
#'
#' @param conn A `creel_connection` object created by [creel_connect()].
#' @param ... Reserved for future arguments.
#'
#' @return A data frame with canonical columns: `catch_uid`, `interview_uid`,
#'   `species` (character), `catch_count` (numeric), `catch_type` (character).
#'   Extra CSV columns are dropped.
#' @export
fetch_catch <- function(conn, ...) UseMethod("fetch_catch")

#' @export
fetch_catch.creel_connection_csv <- function(conn, ...) {
  df <- .read_csv_safe(conn$con$catch)
  rename_map <- c(
    catch_uid     = "catch_uid_col",
    interview_uid = "interview_uid_col",
    species       = "species_col",
    catch_count   = "catch_count_col",
    catch_type    = "catch_type_col"
  )
  df <- .rename_to_canonical(df, conn$schema, rename_map)
  # Coerce species to character BEFORE validation (AGENCY integer codes)
  if ("species"     %in% names(df)) df$species     <- as.character(df$species)
  if ("catch_count" %in% names(df)) df$catch_count <- .coerce_numeric(df$catch_count, "catch_count")
  if ("catch_type"  %in% names(df)) df$catch_type  <- as.character(df$catch_type)
  validate_fetch_catch(df) # nolint: object_usage_linter
  df
}

#' @export
fetch_catch.creel_connection_sqlserver <- function(conn, ...) {
  cli::cli_abort("SQL Server fetch_catch() not yet implemented (Phase 69).")
}

#' @export
fetch_catch.creel_connection_api <- function(conn, ...) {
  raw_df <- .api_fetch(conn$con, "catch")

  # Early return for empty API response
  if (nrow(raw_df) == 0L) {
    return(data.frame(
      catch_uid        = integer(0),
      interview_uid    = character(0),
      species          = character(0),
      catch_count      = numeric(0),
      catch_type       = character(0),
      stringsAsFactors = FALSE
    ))
  }

  fm <- conn$con$api_field_map$catch
  api_rename_map <- c(
    interview_uid = fm$interview_uid,
    species       = fm$species,
    catch_count   = fm$catch_count,
    catch_type    = fm$catch_type
  )
  api_rename_map <- api_rename_map[!is.na(api_rename_map) & nzchar(api_rename_map)]
  df <- .rename_api_to_canonical(raw_df, api_rename_map)

  # UID synthesis: catch_uid absent from API response -- synthesize as row index (D-05, D-06)
  if (!"catch_uid" %in% names(df)) {
    df$catch_uid <- seq_len(nrow(df))
  }

  if ("species"     %in% names(df)) df$species     <- as.character(df$species)
  if ("catch_count" %in% names(df)) df$catch_count <- .coerce_numeric(df$catch_count, "catch_count")
  if ("catch_type"  %in% names(df)) df$catch_type  <- as.character(df$catch_type)

  validate_fetch_catch(df) # nolint: object_usage_linter
  df
}


#' Load harvest length data from a creel connection
#'
#' @description
#' Reads the harvest lengths table from a creel data source, renames columns
#' to canonical tidycreel names, coerces types, validates, and returns a
#' data frame ready for [tidycreel::add_lengths()].
#'
#' @param conn A `creel_connection` object created by [creel_connect()].
#' @param ... Reserved for future arguments.
#'
#' @return A data frame with canonical columns: `length_uid`, `interview_uid`,
#'   `species` (character), `length_mm` (numeric), `length_type` (character).
#'   Extra CSV columns are dropped.
#' @export
fetch_harvest_lengths <- function(conn, ...) UseMethod("fetch_harvest_lengths")

#' @export
fetch_harvest_lengths.creel_connection_csv <- function(conn, ...) {
  df <- .read_csv_safe(conn$con$harvest_lengths)
  rename_map <- c(
    length_uid    = "length_uid_col",
    interview_uid = "interview_uid_col",
    species       = "species_col",
    length_mm     = "length_mm_col",
    length_type   = "length_type_col"
  )
  df <- .rename_to_canonical(df, conn$schema, rename_map)
  if ("species"     %in% names(df)) df$species     <- as.character(df$species)
  if ("length_mm"   %in% names(df)) df$length_mm   <- .coerce_numeric(df$length_mm, "length_mm")
  if ("length_type" %in% names(df)) df$length_type <- as.character(df$length_type)
  validate_fetch_harvest_lengths(df) # nolint: object_usage_linter
  df
}

#' @export
fetch_harvest_lengths.creel_connection_sqlserver <- function(conn, ...) {
  cli::cli_abort("SQL Server fetch_harvest_lengths() not yet implemented (Phase 69).")
}

#' @export
fetch_harvest_lengths.creel_connection_api <- function(conn, ...) {
  raw_df <- .api_fetch(conn$con, "harvest_lengths")

  # Early return for empty API response
  if (nrow(raw_df) == 0L) {
    return(data.frame(
      length_uid       = integer(0),
      interview_uid    = character(0),
      species          = character(0),
      length_mm        = numeric(0),
      length_type      = character(0),
      stringsAsFactors = FALSE
    ))
  }

  fm <- conn$con$api_field_map$harvest_lengths
  # NOTE: AGENCY harvest lengths use "iiUID" (no underscore), unlike "api_UID" in interviews/catch
  api_rename_map <- c(
    interview_uid = fm$interview_uid,
    species       = fm$species,
    length_mm     = fm$length_mm
  )
  api_rename_map <- api_rename_map[!is.na(api_rename_map) & nzchar(api_rename_map)]
  df <- .rename_api_to_canonical(raw_df, api_rename_map)

  # UID synthesis: length_uid absent from API response -- synthesize as row index (D-05, D-06)
  if (!"length_uid" %in% names(df)) {
    df$length_uid <- seq_len(nrow(df))
  }

  # Constant injection: API returns no length_type flag for harvest endpoint (CONTEXT.md D-07)
  df$length_type <- "harvest"

  if ("species"   %in% names(df)) df$species   <- as.character(df$species)
  if ("length_mm" %in% names(df)) df$length_mm <- .coerce_numeric(df$length_mm, "length_mm")

  validate_fetch_harvest_lengths(df) # nolint: object_usage_linter
  df
}


#' Load release length data from a creel connection
#'
#' @description
#' Reads the release lengths table from a creel data source, renames columns
#' to canonical tidycreel names, coerces types, validates, and returns a
#' data frame ready for [tidycreel::add_lengths()].
#'
#' @param conn A `creel_connection` object created by [creel_connect()].
#' @param ... Reserved for future arguments.
#'
#' @return A data frame with canonical columns: `length_uid`, `interview_uid`,
#'   `species` (character), `length_mm` (numeric), `length_type` (character).
#'   Extra CSV columns are dropped.
#' @export
fetch_release_lengths <- function(conn, ...) UseMethod("fetch_release_lengths")

#' @export
fetch_release_lengths.creel_connection_csv <- function(conn, ...) {
  df <- .read_csv_safe(conn$con$release_lengths)
  rename_map <- c(
    length_uid    = "length_uid_col",
    interview_uid = "interview_uid_col",
    species       = "species_col",
    length_mm     = "length_mm_col",
    length_type   = "length_type_col"
  )
  df <- .rename_to_canonical(df, conn$schema, rename_map)
  if ("species"     %in% names(df)) df$species     <- as.character(df$species)
  if ("length_mm"   %in% names(df)) df$length_mm   <- .coerce_numeric(df$length_mm, "length_mm")
  if ("length_type" %in% names(df)) df$length_type <- as.character(df$length_type)
  validate_fetch_release_lengths(df) # nolint: object_usage_linter
  df
}

#' @export
fetch_release_lengths.creel_connection_sqlserver <- function(conn, ...) {
  cli::cli_abort("SQL Server fetch_release_lengths() not yet implemented (Phase 69).")
}

#' @export
fetch_release_lengths.creel_connection_api <- function(conn, ...) {
  raw_df <- .api_fetch(conn$con, "release_lengths")

  # Early return for empty API response
  if (nrow(raw_df) == 0L) {
    return(data.frame(
      length_uid       = integer(0),
      interview_uid    = character(0),
      species          = character(0),
      length_mm        = numeric(0),
      length_type      = character(0),
      stringsAsFactors = FALSE
    ))
  }

  fm <- conn$con$api_field_map$release_lengths
  # NOTE: AGENCY release lengths use "iiUID" (no underscore), same as harvest lengths
  # api_Count (binned count) is not in the canonical field map; dropped by .rename_api_to_canonical
  api_rename_map <- c(
    interview_uid = fm$interview_uid,
    species       = fm$species,
    length_mm     = fm$length_mm
  )
  api_rename_map <- api_rename_map[!is.na(api_rename_map) & nzchar(api_rename_map)]
  df <- .rename_api_to_canonical(raw_df, api_rename_map)

  # UID synthesis: length_uid absent from API response -- synthesize as row index (D-05, D-06)
  if (!"length_uid" %in% names(df)) {
    df$length_uid <- seq_len(nrow(df))
  }

  # Constant injection: API returns no length_type flag for release endpoint (CONTEXT.md D-07)
  df$length_type <- "release"

  if ("species"   %in% names(df)) df$species   <- as.character(df$species)
  if ("length_mm" %in% names(df)) df$length_mm <- .coerce_numeric(df$length_mm, "length_mm")

  validate_fetch_release_lengths(df) # nolint: object_usage_linter
  df
}
