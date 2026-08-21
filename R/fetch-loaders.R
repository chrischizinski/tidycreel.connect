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

# Internal: rename raw API columns to canonical names.
# api_rename_map: named character vector where names = canonical names,
#   values = the raw JSON field names the connection was configured with
#   (e.g., c(interview_uid = "InterviewID", date = "SurveyDate")).
# Columns in api_rename_map but absent from df are dropped.
# table: canonical table name, used to attribute the dropped-column message.
# also_used: raw field names the caller consumes outside the map (the interview
#   effort fields are combined arithmetically, not renamed), so they are not
#   reported as lost.
# Returns a plain data.frame with only matched canonical columns.
.rename_api_to_canonical <- function(df, api_rename_map, table, also_used = character(0)) {
  keep <- character(0)
  for (canonical in names(api_rename_map)) {
    api_col <- api_rename_map[[canonical]]
    if (api_col %in% names(df)) {
      keep[[canonical]] <- api_col
    }
  }
  result <- df[, keep, drop = FALSE]
  names(result) <- names(keep)
  .report_dropped_cols(names(df), c(keep, also_used), table, "api_field_map")
  result
}

# Internal: rename CSV columns to canonical names using schema field mapping.
# rename_map: named character vector where names = canonical names,
#   values = schema field names (e.g., c(date = "date_col", ...)).
# Columns not found in the data frame are dropped (optional mapping).
# table: canonical table name, used to attribute the dropped-column message.
# Returns a plain data.frame with only canonical columns.
.rename_to_canonical <- function(df, schema, rename_map, table) {
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
  .report_dropped_cols(names(df), keep, table, "creel_schema")
  result
}

# Internal: report source columns that did not survive the rename.
# An inform, not a warning: dropping an unmapped column is the documented
# behaviour, and the point is that the loss is visible rather than that it is
# wrong. The columns are named so the caller can tell an ignorable extra column
# from a load-bearing one they expected to be carried -- the bus-route interview
# columns disappeared this way and add_interviews() then aborted with an error
# that pointed nowhere near the cause (GH #126).
.report_dropped_cols <- function(source_cols, keep, table, route) {
  dropped <- setdiff(source_cols, unname(keep))
  if (length(dropped) == 0L) {
    return(invisible(NULL))
  }
  # Truncated: a source table can carry dozens of fields, most of them genuinely
  # unused, and an untruncated list would bury the load-bearing ones.
  shown <- cli::cli_vec(dropped, list("vec-trunc" = 10L)) # nolint: object_usage_linter
  route_fn <- if (identical(route, "creel_schema")) { # nolint: object_usage_linter
    "tidycreel::creel_schema"
  } else {
    "creel_connect_api"
  }
  cli::cli_inform(c(
    "i" = "{table}: {length(dropped)} source column{?s} not carried through: {.field {shown}}.",
    " " = "Map what you need downstream via {.arg {route}} in {.fn {route_fn}}."
  ))
  invisible(NULL)
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
#'   `trip_status` (character).
#'
#'   Six further columns are carried when the schema (CSV) or `api_field_map`
#'   (API) maps them, and omitted otherwise: `n_anglers` (numeric),
#'   `angler_type` (character), `site` (character), `circuit` (character),
#'   `n_counted` (numeric), `n_interviewed` (numeric). Map `n_anglers` whenever
#'   the source records party size -- without it [tidycreel::add_interviews()]
#'   assumes one angler per interview and party-hours are consumed as
#'   angler-hours. `site` and `circuit` are what a bus-route design joins the
#'   site inclusion probability on.
#'
#'   Source columns outside the map are dropped, and each fetch reports which
#'   ones by name.
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
    trip_status   = "trip_status_col",
    # Optional, all previously dropped without a word (GH #126). n_anglers and
    # angler_type are what mean_party_size() and derive_angler_count() consume;
    # without them add_interviews() falls back to one angler per interview and
    # party-hours are consumed as angler-hours. site, circuit, n_counted and
    # n_interviewed are what the bus-route expansion joins on.
    n_anglers     = "n_anglers_col",
    angler_type   = "angler_type_col",
    site          = "site_col",
    circuit       = "circuit_col",
    n_counted     = "n_counted_col",
    n_interviewed = "n_interviewed_col"
  )
  df <- .rename_to_canonical(df, conn$schema, rename_map, "interviews")
  if ("date"        %in% names(df)) df$date        <- .coerce_date(df$date, "date")
  if ("catch_count" %in% names(df)) df$catch_count <- .coerce_numeric(df$catch_count, "catch_count")
  if ("effort"      %in% names(df)) df$effort      <- .coerce_numeric(df$effort, "effort")
  if ("trip_status" %in% names(df)) df$trip_status <- as.character(df$trip_status)
  # Coerced rather than merely passed through: these feed party-size and
  # bus-route arithmetic, and a numeric column arriving as character would be
  # accepted by the optional validator and fail much later.
  for (nm in c("n_anglers", "n_counted", "n_interviewed")) {
    if (nm %in% names(df)) df[[nm]] <- .coerce_numeric(df[[nm]], nm)
  }
  for (nm in c("angler_type", "site", "circuit")) {
    if (nm %in% names(df)) df[[nm]] <- as.character(df[[nm]])
  }
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
  # catch_count belongs here only where the interviews endpoint reports a
  # per-trip total; where catch lives in its own endpoint the field is unnamed
  # and users aggregate from fetch_catch(). c() drops NULL entries silently, so
  # an unnamed field is simply absent from the result.
  # The optional interview fields (GH #126). None of them is named by a default:
  # which raw field holds a party size, a site or a circuit is a property of the
  # source API, so the caller names them through api_field_map. Unnamed entries
  # are NULL and c() omits them, so an API that returns none of these is
  # unaffected -- but one that returns them is no longer silently stripped of a
  # party size (party-hours read as angler-hours) or of the columns a bus-route
  # design joins its inclusion probabilities on.
  api_rename_map <- c(
    interview_uid = fm$interview_uid,
    date          = fm$date,
    catch_count   = fm$catch_count,
    trip_status   = fm$trip_status,
    n_anglers     = fm$n_anglers,
    angler_type   = fm$angler_type,
    site          = fm$site,
    circuit       = fm$circuit,
    n_counted     = fm$n_counted,
    n_interviewed = fm$n_interviewed
  )
  api_rename_map <- api_rename_map[!is.na(api_rename_map) & nzchar(api_rename_map)]

  # Effort: arithmetic from two raw fields (API-01); or single field when effort_minutes is NULL
  hours_col   <- fm$effort_hours
  minutes_col <- fm$effort_minutes
  # Reported as carried, not dropped: they are consumed by the arithmetic below.
  effort_used <- unlist(c(hours_col, minutes_col))
  df <- .rename_api_to_canonical(raw_df, api_rename_map, "interviews", also_used = effort_used)

  if (!is.null(hours_col) && nzchar(hours_col) && hours_col %in% names(raw_df)) {
    df$effort <- .coerce_numeric(raw_df[[hours_col]], hours_col)
    if (!is.null(minutes_col) && nzchar(minutes_col) && minutes_col %in% names(raw_df)) {
      df$effort <- df$effort + .coerce_numeric(raw_df[[minutes_col]], minutes_col) / 60
    }
  }

  if ("date"        %in% names(df)) df$date        <- .parse_api_date(df$date)
  if ("catch_count" %in% names(df)) df$catch_count <- .coerce_numeric(df$catch_count, "catch_count")
  if ("trip_status" %in% names(df)) df$trip_status <- as.character(df$trip_status)
  # Same coercion contract as the CSV path: party-size and bus-route arithmetic
  # consume these, so the type is settled here rather than several stages later.
  for (nm in c("n_anglers", "n_counted", "n_interviewed")) {
    if (nm %in% names(df)) df[[nm]] <- .coerce_numeric(df[[nm]], nm)
  }
  # angler_type, site and circuit are labels: a source that codes them as
  # integers still means them as categories, and character keeps arithmetic from
  # consuming a code as a quantity.
  for (nm in c("angler_type", "site", "circuit")) {
    if (nm %in% names(df)) df[[nm]] <- as.character(df[[nm]])
  }

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
  df <- .rename_to_canonical(df, conn$schema, rename_map, "counts")
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
  df <- .rename_api_to_canonical(raw_df, api_rename_map, "counts")

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
  df <- .rename_to_canonical(df, conn$schema, rename_map, "catch")
  # Coerce species to character BEFORE validation: a source may code species as
  # integers, and a code is a label rather than a quantity.
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
  df <- .rename_api_to_canonical(raw_df, api_rename_map, "catch")

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
  df <- .rename_to_canonical(df, conn$schema, rename_map, "harvest_lengths")
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
  # NOTE: an API may spell the interview UID differently on this endpoint than
  # on interviews/catch, which is why it is named per endpoint.
  api_rename_map <- c(
    interview_uid = fm$interview_uid,
    species       = fm$species,
    length_mm     = fm$length_mm
  )
  api_rename_map <- api_rename_map[!is.na(api_rename_map) & nzchar(api_rename_map)]
  df <- .rename_api_to_canonical(raw_df, api_rename_map, "harvest_lengths")

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
  df <- .rename_to_canonical(df, conn$schema, rename_map, "release_lengths")
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
  # NOTE: named per endpoint for the same reason as harvest lengths.
  # A binned-count field, where a source has one, is not part of the canonical
  # map and is dropped by .rename_api_to_canonical (reported, not silent).
  api_rename_map <- c(
    interview_uid = fm$interview_uid,
    species       = fm$species,
    length_mm     = fm$length_mm
  )
  api_rename_map <- api_rename_map[!is.na(api_rename_map) & nzchar(api_rename_map)]
  df <- .rename_api_to_canonical(raw_df, api_rename_map, "release_lengths")

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
