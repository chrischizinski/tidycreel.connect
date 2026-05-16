# tidycreel.connect: fetch_*() generics, CSV methods, and SQL Server stubs
# Phase 68: FETCH-01 through FETCH-06, BACKEND-01, BACKEND-04

# Internal: load CSV with native BOM stripping (no locale argument needed)
.read_csv_safe <- function(path) {
  readr::read_csv(path, show_col_types = FALSE, progress = FALSE)
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
  if ("date" %in% names(df)) {
    df$date <- as.Date(df$date, tryFormats = c("%Y-%m-%d", "%m/%d/%Y"))
  }
  if ("catch_count" %in% names(df)) df$catch_count <- as.numeric(df$catch_count)
  if ("effort" %in% names(df)) df$effort <- as.numeric(df$effort)
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

  # Early return for empty API response — avoids logical-typed columns failing validation
  if (nrow(raw_df) == 0L) {
    return(data.frame(
      interview_uid    = character(0),
      date             = as.Date(character(0)),
      catch_count      = numeric(0),
      effort           = numeric(0),
      trip_status      = character(0),
      stringsAsFactors = FALSE
    ))
  }

  # Hardcoded AGENCY field names — do NOT route through creel_schema (CONTEXT.md D-01 through D-04)
  api_rename_map <- c(
    interview_uid = "api_UID",
    date          = "api_Date",
    catch_count   = "Num",          # TODO: confirm field name with live API
    trip_status   = "api_TripKind"   # TODO: confirm field name with live API
  )
  df <- .rename_api_to_canonical(raw_df, api_rename_map)

  # Effort: arithmetic from two raw fields — only method requiring field arithmetic (API-01)
  hours_col   <- "api_TimeFishedHours"   # TODO: confirm field name with live API
  minutes_col <- "api_TimeFishedMinutes" # TODO: confirm field name with live API
  if (hours_col %in% names(raw_df) && minutes_col %in% names(raw_df)) {
    df$effort <- as.numeric(raw_df[[hours_col]]) +
                 as.numeric(raw_df[[minutes_col]]) / 60
  }

  if ("date" %in% names(df))        df$date        <- .parse_api_date(df$date)
  if ("catch_count" %in% names(df)) df$catch_count <- as.numeric(df$catch_count)
  if ("trip_status" %in% names(df)) df$trip_status <- as.character(df$trip_status)

  validate_fetch_interviews(df) # nolint: object_usage_linter
  df
}


#' Load count data from a creel connection
#'
#' @description
#' Reads the counts table from a creel data source, renames columns to
#' canonical tidycreel names, coerces types, validates, and returns a
#' data frame ready for [tidycreel::add_counts()].
#'
#' @param conn A `creel_connection` object created by [creel_connect()].
#' @param ... Reserved for future arguments.
#'
#' @return A data frame with canonical columns: `date` (Date),
#'   `angler_count` (numeric). Extra CSV columns are dropped.
#' @export
fetch_counts <- function(conn, ...) UseMethod("fetch_counts")

#' @export
fetch_counts.creel_connection_csv <- function(conn, ...) {
  df <- .read_csv_safe(conn$con$counts)
  rename_map <- c(
    date         = "date_col",
    angler_count = "count_col"
  )
  df <- .rename_to_canonical(df, conn$schema, rename_map)
  if ("date" %in% names(df)) {
    df$date <- as.Date(df$date, tryFormats = c("%Y-%m-%d", "%m/%d/%Y"))
  }
  if ("angler_count" %in% names(df)) df$angler_count <- as.numeric(df$angler_count)
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
      angler_count     = numeric(0),
      stringsAsFactors = FALSE
    ))
  }

  # Hardcoded AGENCY field names — do NOT route through creel_schema (CONTEXT.md D-01 through D-04)
  api_rename_map <- c(
    date         = "api_Date",
    angler_count = "api_NumberAnglers"  # TODO: confirm field name with live API
  )
  df <- .rename_api_to_canonical(raw_df, api_rename_map)

  if ("date" %in% names(df))         df$date         <- .parse_api_date(df$date)
  if ("angler_count" %in% names(df)) df$angler_count  <- as.numeric(df$angler_count)

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
  if ("species" %in% names(df)) df$species <- as.character(df$species)
  if ("catch_count" %in% names(df)) df$catch_count <- as.numeric(df$catch_count)
  if ("catch_type" %in% names(df)) df$catch_type <- as.character(df$catch_type)
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

  # Hardcoded AGENCY field names — do NOT route through creel_schema (CONTEXT.md D-01 through D-04)
  api_rename_map <- c(
    interview_uid = "api_UID",
    species       = "api_Species",
    catch_count   = "Num",
    catch_type    = "CatchCategory"
  )
  df <- .rename_api_to_canonical(raw_df, api_rename_map)

  # UID synthesis: catch_uid absent from API response — synthesize as row index (D-05, D-06)
  if (!"catch_uid" %in% names(df)) {
    df$catch_uid <- seq_len(nrow(df))
  }

  if ("species" %in% names(df))     df$species     <- as.character(df$species)
  if ("catch_count" %in% names(df)) df$catch_count <- as.numeric(df$catch_count)
  if ("catch_type" %in% names(df))  df$catch_type  <- as.character(df$catch_type)

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
  if ("species" %in% names(df)) df$species <- as.character(df$species)
  if ("length_mm" %in% names(df)) df$length_mm <- as.numeric(df$length_mm)
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

  # Hardcoded AGENCY field names — do NOT route through creel_schema (CONTEXT.md D-01 through D-04)
  # NOTE: harvest/release lengths use iiUID (no underscore), NOT api_UID used by interviews/catch
  api_rename_map <- c(
    interview_uid = "iiUID",       # NOTE: no underscore — differs from api_UID in interviews/catch
    species       = "api_Species",
    length_mm     = "api_Length"
  )
  df <- .rename_api_to_canonical(raw_df, api_rename_map)

  # UID synthesis: length_uid absent from API response — synthesize as row index (D-05, D-06)
  if (!"length_uid" %in% names(df)) {
    df$length_uid <- seq_len(nrow(df))
  }

  # Constant injection: API returns no length_type flag for harvest endpoint (CONTEXT.md D-07)
  df$length_type <- "harvest"

  if ("species" %in% names(df))   df$species   <- as.character(df$species)
  if ("length_mm" %in% names(df)) df$length_mm <- as.numeric(df$length_mm)

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
  if ("species" %in% names(df)) df$species <- as.character(df$species)
  if ("length_mm" %in% names(df)) df$length_mm <- as.numeric(df$length_mm)
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

  # Hardcoded AGENCY field names — do NOT route through creel_schema (CONTEXT.md D-01 through D-04)
  # NOTE: release lengths use iiUID (no underscore) same as harvest lengths
  api_rename_map <- c(
    interview_uid = "iiUID",          # NOTE: no underscore
    species       = "api_Species",
    length_mm     = "api_LengthBand"
    # api_Count is NOT renamed — no canonical target; dropped silently by .rename_api_to_canonical
    # TODO: confirm api_Count aggregation policy with live API (CONTEXT.md D-03)
  )
  df <- .rename_api_to_canonical(raw_df, api_rename_map)

  # UID synthesis: length_uid absent from API response — synthesize as row index (D-05, D-06)
  if (!"length_uid" %in% names(df)) {
    df$length_uid <- seq_len(nrow(df))
  }

  # Constant injection: API returns no length_type flag for release endpoint (CONTEXT.md D-07)
  df$length_type <- "release"

  if ("species" %in% names(df))   df$species   <- as.character(df$species)
  if ("length_mm" %in% names(df)) df$length_mm <- as.numeric(df$length_mm)

  validate_fetch_release_lengths(df) # nolint: object_usage_linter
  df
}
