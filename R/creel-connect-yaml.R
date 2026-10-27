# tidycreel.connect: YAML-based connection constructor
# Phase 67: CONNECT-03, CONNECT-04

#' Create a creel connection from a YAML config file
#'
#' @description
#' `creel_connect_from_yaml()` reads a YAML configuration file and creates a
#' validated `creel_connection` object. All required keys and types are
#' validated before any connection is attempted (fail-fast).
#'
#' Credentials must never be stored as plain text in the YAML file. Use the
#' `config` package's `!expr` tag to inject environment variables:
#' ```yaml
#' username: !expr Sys.getenv("CREEL_USER")
#' password: !expr Sys.getenv("CREEL_PASS")
#' ```
#'
#' ## API profiles
#'
#' With `backend: api`, the profile carries the whole API contract -- `base_url`,
#' `uid_param`, `creel_uids`, `endpoints` and `field_map` -- because none of it
#' ships with the package. A commented template with invented names is
#' installed at
#' ```r
#' system.file("extdata", "api-profile-example.yml", package = "tidycreel.connect")
#' ```
#' Keeping the profile outside your analysis code is what lets the same script
#' run against a different organisation's API by pointing at a different file.
#'
#' An optional `pagination:` block says how the API pages its responses and is
#' passed straight to [creel_connect_api()], which documents the styles. Leave
#' it out for an API that returns every record at once -- a response that proves
#' otherwise then aborts rather than being read as the complete dataset.
#'
#' Two more optional keys describe the *shape* of a response rather than the
#' number of them. `records_path:` names the member holding the records for an
#' API that wraps them in an envelope, and `total_path:` names the member
#' holding the count for the whole query. Both are passed straight to
#' [creel_connect_api()]. Write a nested path as a sequence:
#' ```yaml
#' records_path: results        # {"count": 42, "results": [...]}
#' total_path: count
#'
#' records_path: [data, items]  # {"data": {"items": [...]}}
#' ```
#' Leave them out for an API whose body is the JSON array itself.
#'
#' ## CSV profiles
#'
#' The CSV backend resolves every canonical column through the schema, so the
#' profile has to say what your columns are called. Name them under
#' `schema: columns:`, keyed by tidycreel's canonical name with no `_col`
#' suffix:
#' ```yaml
#' schema:
#'   survey_type: instantaneous
#'   columns:
#'     interview_uid: InterviewID
#'     date: SurveyDate
#'     effort: HoursFished
#' ```
#' A column the source already names the way tidycreel does needs no entry: the
#' fetch takes it by its canonical name and says which columns it took that way.
#' Declare it anyway to state the mapping explicitly. A column that is neither
#' mapped nor canonically named is dropped on the way in, which
#' `fetch_interviews()` reports as a missing required column. Note that an entry
#' naming a column the source does not have stays a drop — it is not rescued by
#' a canonically-named column, because a mapping that does not match is a
#' configuration error worth seeing. A commented template is installed at
#' ```r
#' system.file("extdata", "csv-profile-example.yml", package = "tidycreel.connect")
#' ```
#' `backend: api` ignores column mappings and reads raw JSON keys from
#' `field_map`, so a `columns:` block there is an error rather than a no-op.
#'
#' `backend: sqlserver` resolves a `columns:` block exactly as `csv` does: both
#' read a whole table and rename it through the schema. It additionally needs
#' the table names, which the same `schema:` block carries as
#' `interviews_table`, `counts_table`, `catch_table` and
#' `harvest_lengths_table` / `release_lengths_table` (both falling back to
#' `lengths_table`).
#'
#' ## Corrections
#'
#' An optional top-level `corrections:` key names a CSV of documented fixes to
#' the fetched data, read relative to the profile's directory:
#' ```yaml
#' corrections: corrections.csv
#' ```
#' ```
#' creel_uid,table,date,field,from,to,reason
#' ,counts,2025-06-14,period,1,2,Section 3 counted PM; sheet says AM
#' ```
#' Each row changes `field` from `from` to `to` on the `table` records of that
#' `date` (`interviews` or `counts`; catch and lengths carry no date). Names
#' and values are tidycreel's, after `field_map`/`columns` and `value_maps`.
#' Every row needs a `reason`. Leave `creel_uid` blank on a CSV or SQL Server
#' profile, or on an API profile with one creel; name the creel on an API
#' profile with several. Rows for creels the profile does not fetch are
#' ignored, so one file can serve them all.
#'
#' `NA` in `from` matches a missing value and in `to` writes one. Quote a
#' value that contains a comma.
#'
#' `fetch_interviews()` and `fetch_counts()` apply them in file order, before
#' validation, and list each change once per connection
#' (`creel_message_corrections_applied`) by line, date, field and count. The
#' values themselves are not printed, since one can be personal (a ZIP code);
#' keep the `reason` free of them too. The result carries the rows applied,
#' with the number of records each changed, as `attr(x, "corrections")`, for a
#' report to list. A correction that matches no record is an error
#' (`creel_error_correction_unmatched`): the data changed underneath it, and it
#' has to be checked again rather than silently do nothing.
#'
#' ## Cleanup
#'
#' An optional top-level `cleanup:` block removes rows that are artifacts of
#' how the source serves data rather than records. Every step is off unless
#' named `true`:
#' ```yaml
#' cleanup:
#'   interviews:
#'     drop_placeholders: true
#'     collapse_repeats: true
#'   counts:
#'     drop_placeholders: true
#' ```
#' `drop_placeholders` drops rows that carry a value in no column but
#' `creel_uid`, `date` and the strata: rows a source writes for a sampled date
#' on which nothing was recorded. A blank string counts as no value. Rows are
#' judged on the fetched columns, so a source column that holds data the
#' analysis needs must be mapped to count. A blank count row is dropped, never read as
#' a zero. An interview row with no `interview_uid` that does carry data is an
#' error (`creel_error_cleanup_rows_without_uid`), not a placeholder.
#'
#' `collapse_repeats` keeps one of each set of interview rows identical in
#' every fetched column: a long-format source repeats each interview once per
#' questionnaire answer, which `fetch_interviews()` otherwise warns about
#' (`creel_warning_fetch_created_duplicates`) and returns. If one interview
#' still has two rows that differ, the fetch aborts
#' (`creel_error_cleanup_conflicting_repeats`) and names the columns, since
#' choosing one would be a guess. Counts have no `collapse_repeats`: two
#' identical count rows can be two real counts.
#'
#' Cleanup runs after corrections. The fetch reports what it removed once per
#' connection (`creel_message_rows_cleaned`), and the result carries the
#' counts as `attr(x, "cleanup")`: `rows_in`, `placeholders_dropped`,
#' `repeats_collapsed` and `rows_kept`.
#'
#' ## Time zone
#'
#' An optional top-level `tz:` key names the time zone of the water, as one
#' IANA name from [OlsonNames()]:
#' ```yaml
#' tz: America/Chicago
#' ```
#' Night designs need one (see [tidycreel::creel_design()]), and the profile is
#' where the water is described, so it saves repeating the zone in every
#' script. The value is checked when the profile is read, kept on the
#' connection as `conn$tz`, and, when the `tidycreel.tz` option is unset, set
#' as that option for the session, with a one-line message saying so.
#' tidycreel reads a `tz =` argument before the option, so an explicit
#' argument always wins.
#'
#' An option already set to a different zone is kept, with a warning: it was
#' set on purpose, perhaps by another profile, and replacing it silently would
#' move that water's night designs into this one's zone. Pass
#' `tz = conn$tz` to [tidycreel::creel_design()] for the water this profile
#' describes.
#'
#' @param path Path to the YAML config file. Must exist.
#' @param config Environment block to use (default: `"default"`). Passed to
#'   `config::get(config = ...)`. Common values: `"default"`, `"production"`,
#'   `"staging"`.
#'
#' @return A `creel_connection` S3 object.
#' @export
#' @examples
#' \dontrun{
#' conn <- creel_connect_from_yaml("config.yml")
#' conn <- creel_connect_from_yaml("config.yml", config = "production")
#' }
creel_connect_from_yaml <- function(path, config = "default") {
  if (!requireNamespace("config", quietly = TRUE)) {
    cli::cli_abort(c(
      "Package {.pkg config} is required for YAML-based connections.",
      "i" = "Install it with {.code install.packages('config')}."
    ))
  }
  if (!file.exists(path)) {
    cli::cli_abort("{.arg path} does not exist: {.file {path}}")
  }
  # Load all keys at once -- use_parent=FALSE prevents searching parent directories
  cfg <- config::get(value = NULL, config = config, file = path, use_parent = FALSE)
  if (is.null(cfg) || !is.list(cfg)) {
    cli::cli_abort(c(
      "Config block {.val {config}} not found or empty in {.file {path}}.",
      "i" = "Check that the YAML file has a {.code {config}:} top-level block."
    ))
  }
  # Pre-validate all required keys and types before any connection attempt
  .validate_yaml_config(cfg, path)
  # Build connection from validated config
  conn <- .build_creel_conn(cfg)
  # After the build, so a profile that fails to connect leaves the session's
  # options as they were.
  if (!is.null(cfg$corrections)) {
    cx_path <- .profile_relative(cfg$corrections, path)
    conn$corrections <- .read_corrections(cx_path, conn) # nolint: object_usage_linter
  }
  if (!is.null(cfg$cleanup)) {
    conn$cleanup <- cfg$cleanup
  }
  if (!is.null(cfg$tz)) {
    conn$tz <- cfg$tz
    .apply_profile_tz(cfg$tz, path)
  }
  conn
}

# Internal: a path named in a profile, read relative to the profile's own
# directory unless absolute, so the profile and its files move together.
#' @noRd
.profile_relative <- function(p, path) {
  # Absolute: `/`, `~`, a drive (`C:/`, `C:\`) or a UNC share (`\\server`).
  absolute <- grepl("^(/|~|[A-Za-z]:[/\\\\]|\\\\\\\\)", p)
  if (absolute) p else file.path(dirname(path), p)
}

# Internal: set options(tidycreel.tz) from a profile's tz, when unset
# (tidycreel#407 decision, 2026-10-06). A different value already set is kept
# and warned about, never replaced silently.
#' @noRd
.apply_profile_tz <- function(tz, path) {
  current <- getOption("tidycreel.tz")
  if (is.null(current)) {
    options(tidycreel.tz = tz)
    connect_inform( # nolint: object_usage_linter
      c("i" = "Set {.code options(tidycreel.tz = \"{tz}\")} for this session, \\
               from {.file {path}}."),
      class = "creel_message_tz_option_set"
    )
  } else if (!identical(current, tz)) {
    cli::cli_warn(
      c(
        "The profile's time zone {.val {tz}} differs from the \\
         {.field tidycreel.tz} option, {.val {current}}, which is kept.",
        "i" = "Night designs are read in {.val {current}} unless given \\
               {.arg tz}. For this profile's water, pass \\
               {.code tz = conn$tz} to {.fn tidycreel::creel_design}."
      ),
      class = c("creel_warning_tz_option_differs", "creel_warning")
    )
  }
  invisible(NULL)
}

# Internal: validate required YAML keys before any connection attempt
# Aborts with cli_abort() listing all missing/invalid keys at once
#' @noRd
.validate_yaml_config <- function(cfg, path) {
  # 1. Require 'backend' key
  if (is.null(cfg$backend)) {
    cli::cli_abort(c(
      "Required key {.field backend} is missing from YAML config: {.file {path}}",
      "i" = "Add {.code backend: csv}, {.code backend: sqlserver} or \\
             {.code backend: api} to your config."
    ))
  }
  backend <- cfg$backend

  # 2. Validate backend value
  valid_backends <- c("csv", "sqlserver", "api")
  if (!backend %in% valid_backends) {
    cli::cli_abort(c(
      "{.field backend} must be one of {.val {valid_backends}}, not {.val {backend}}.",
      "i" = "Check the backend value in {.file {path}}."
    ))
  }

  # 3. Require 'schema' key with 'survey_type'
  if (is.null(cfg$schema)) {
    cli::cli_abort(c(
      "Required key {.field schema} is missing from YAML config: {.file {path}}",
      "i" = "Add a {.code schema:} block with at least {.code survey_type}."
    ))
  }
  if (is.null(cfg$schema$survey_type)) {
    cli::cli_abort(c(
      "Required key {.field schema.survey_type} is missing from YAML config: {.file {path}}",
      "i" = "Add {.code survey_type: instantaneous} (or other valid type) under {.code schema:}."
    ))
  }

  # 4. Backend-specific validation
  if (backend == "csv") {
    if (is.null(cfg$files)) {
      cli::cli_abort(c(
        "Required key {.field files} is missing from CSV YAML config: {.file {path}}",
        "i" = "Add a {.code files:} block with paths for each table."
      ))
    }
    required_tables <- c("interviews", "counts", "catch", "harvest_lengths", "release_lengths")
    missing_tables <- required_tables[!required_tables %in% names(cfg$files)]
    if (length(missing_tables) > 0L) {
      cli::cli_abort(c(
        "Required file path{?s} missing from {.field files} in YAML config: {.file {path}}",
        stats::setNames(
          paste0("{.field files.", missing_tables, "}"),
          rep("x", length(missing_tables))
        )
      ))
    }
  } else if (backend == "api") {
    # The API contract lives in the profile, not in the package: base_url,
    # uid_param, endpoints and field_map all describe one deployment.
    required_keys <- c("base_url", "uid_param", "creel_uids", "endpoints", "field_map")
    missing_keys <- required_keys[vapply(required_keys, function(k) is.null(cfg[[k]]), logical(1))]
    if (!is.null(cfg$schema$columns)) {
      cli::cli_abort(c(
        "{.field schema.columns} does not apply to {.code backend: api}: {.file {path}}",
        "x" = "Column mappings name CSV and SQL Server columns, not JSON fields.",
        "i" = "Name the raw JSON keys in {.field field_map} instead."
      ))
    }
    if (length(missing_keys) > 0L) {
      template <- "system.file(\"extdata\", \"api-profile-example.yml\", package = \"tidycreel.connect\")" # nolint: object_usage_linter, line_length_linter
      cli::cli_abort(c(
        "Required key{?s} missing from api YAML config: {.file {path}}",
        stats::setNames(
          paste0("{.field ", missing_keys, "}"),
          rep("x", length(missing_keys))
        ),
        "i" = "Start from the template profile: {.code {template}}"
      ))
    }
  } else if (backend == "sqlserver") {
    required_keys <- c("server", "database")
    missing_keys <- required_keys[vapply(required_keys, function(k) is.null(cfg[[k]]), logical(1))]
    if (length(missing_keys) > 0L) {
      cli::cli_abort(c(
        "Required key{?s} missing from sqlserver YAML config: {.file {path}}",
        stats::setNames(
          paste0("{.field ", missing_keys, "}"),
          rep("x", length(missing_keys))
        )
      ))
    }
    # Validate credentials exist and are non-empty (!expr returns "" for unset env vars)
    cred_fields <- c("username", "password")
    empty_creds <- cred_fields[vapply(cred_fields, function(k) {
      val <- cfg[[k]]
      is.null(val) || !nzchar(val)
    }, logical(1))]
    if (length(empty_creds) > 0L) {
      cli::cli_abort(c(
        "Credential field{?s} resolved to empty string in YAML config: {.file {path}}",
        stats::setNames(
          paste0("{.field ", empty_creds, "} -- check that the environment variable is set"),
          rep("x", length(empty_creds))
        ),
        "i" = "Use {.code !expr Sys.getenv('VAR_NAME')} and ensure the variable is exported."
      ))
    }
  }

  # 5. Optional corrections: one path. Its contents are checked when read,
  # against the connection it applies to.
  if (!is.null(cfg$corrections) &&
        (!is.character(cfg$corrections) || length(cfg$corrections) != 1L ||
           !nzchar(cfg$corrections))) {
    cli::cli_abort("{.field corrections} must be one file path: {.file {path}}")
  }

  # 6. Optional cleanup: known tables and steps, each true or false.
  if (!is.null(cfg$cleanup)) {
    .validate_cleanup(cfg$cleanup, path) # nolint: object_usage_linter
  }

  # 7. Optional tz: one IANA name. Checked here, so a typo aborts before any
  # connection is made rather than at the first night design.
  if (!is.null(cfg$tz)) {
    tz <- cfg$tz
    if (!is.character(tz) || length(tz) != 1L || is.na(tz) ||
          !tz %in% OlsonNames()) {
      cli::cli_abort(c(
        "{.field tz} must be one time zone name from {.fn OlsonNames}: \\
         {.file {path}}",
        "x" = "Got {.val {tz}}.",
        "i" = "For example {.code tz: America/Chicago}."
      ))
    }
  }
  invisible(cfg)
}

# Internal: build creel_connection from validated config list
#' @noRd
.build_creel_conn <- function(cfg) { # nolint: object_length_linter
  backend <- cfg$backend
  survey_type <- cfg$schema$survey_type

  # Build the creel_schema from the YAML schema block. Column *name* mappings
  # stay out of YAML, but the two fields that are not column names do belong
  # here: the stratum mapping and the value maps. Both describe the source
  # rather than one backend, and a profile that cannot express them leaves the
  # documented route unable to configure an ordinary stratified or coded survey.
  valid_survey_types <- c("instantaneous", "bus_route", "ice", "camera", "aerial")
  if (!survey_type %in% valid_survey_types) {
    cli::cli_abort(c(
      "{.field schema.survey_type} must be one of {.val {valid_survey_types}}, not {.val {survey_type}}.",
      "i" = "Check the {.code survey_type} value under {.code schema:} in your YAML config."
    ))
  }
  schema_args <- list(survey_type = survey_type)
  table_keys <- c(
    "interviews_table", "counts_table", "catch_table",
    "harvest_lengths_table", "release_lengths_table"
  )
  for (k in table_keys) {
    if (!is.null(cfg$schema[[k]])) schema_args[[k]] <- cfg$schema[[k]]
  }
  # Value maps describe the source's vocabulary rather than its column names, so
  # they belong in the profile alongside the field map -- otherwise the feature
  # is unreachable by the route the docs recommend (GH #128). YAML gives each
  # entry as a nested list; creel_schema() wants a named character vector.
  if (!is.null(cfg$schema$value_maps)) {
    schema_args$value_maps <- .yaml_value_maps(cfg$schema$value_maps)
  }
  # Same gap, same reason: without this a profile-configured counts frame
  # reaches add_counts() with no stratum label and any design built with
  # `strata =` aborts -- exactly what GH #171 fixed for a hand-built schema.
  if (!is.null(cfg$schema$strata_cols)) {
    schema_args$strata_cols <- .yaml_strata_cols(cfg$schema$strata_cols)
  }
  # The CSV and SQL Server backends resolve every canonical column through the
  # schema, so without these a profile only works against a source that already
  # uses tidycreel's names -- the one case needing no schema at all (GH #176).
  if (!is.null(cfg$schema$columns)) {
    schema_args <- c(schema_args, .yaml_schema_columns(cfg$schema$columns))
  }
  schema <- do.call(tidycreel::creel_schema, schema_args)

  if (backend == "csv") {
    paths <- as.list(cfg$files)
    .creel_connect_csv(paths, schema) # nolint: object_usage_linter
  } else if (backend == "api") {
    creel_connect_api( # nolint: object_usage_linter
      base_url      = cfg$base_url,
      creel_uids    = as.character(cfg$creel_uids),
      schema        = schema,
      uid_param     = cfg$uid_param,
      endpoints     = as.list(cfg$endpoints),
      auth          = cfg$auth,
      api_field_map = lapply(as.list(cfg$field_map), as.list),
      # Optional: how this deployment paginates. Absent means "returns every
      # record at once", which the fetch then verifies rather than assumes.
      pagination    = if (is.null(cfg$pagination)) NULL else as.list(cfg$pagination),
      # Optional: where the records sit if this API wraps them in an envelope.
      # Absent means the body is the array itself -- which the fetch also
      # verifies rather than assumes, refusing a body it can prove is wrapped.
      # `unlist()` so a nested path may be written as a YAML sequence.
      records_path  = if (is.null(cfg$records_path)) NULL else as.character(unlist(cfg$records_path)), # nolint: line_length_linter
      total_path    = if (is.null(cfg$total_path)) NULL else as.character(unlist(cfg$total_path))
    )
  } else if (backend == "sqlserver") {
    if (!requireNamespace("odbc", quietly = TRUE)) {
      cli::cli_abort(c(
        "Package {.pkg odbc} is required for SQL Server connections.",
        "i" = "Install it with {.code install.packages('odbc')}."
      ))
    }
    # WARNING: cfg$username and cfg$password must come from Sys.getenv() via YAML !expr tags.
    # Do NOT log or print cfg$password -- credentials are validated non-empty above.
    dbi_con <- tryCatch(
      DBI::dbConnect(
        odbc::odbc(),
        Driver   = "ODBC Driver 17 for SQL Server",
        Server   = cfg$server,
        Database = cfg$database,
        UID      = cfg$username,
        PWD      = cfg$password
      ),
      error = function(e) {
        cli::cli_abort(c(
          "Failed to connect to SQL Server {.val {cfg$database}} on {.val {cfg$server}}.",
          "i" = "Check that the server is reachable and credentials are correct.",
          "x" = conditionMessage(e)
        ))
      }
    )
    .creel_connect_dbi(dbi_con, schema) # nolint: object_usage_linter
  }
}


# Internal: turn the YAML `value_maps` block into the named character vectors
# creel_schema() expects. Each column's codes arrive as a nested list; a code
# written unquoted in YAML (1, true) parses as a number or logical, so every
# name and value is made character before creel_schema() validates them.
#' @noRd
.yaml_value_maps <- function(block) {
  if (!is.list(block) || length(block) == 0L || is.null(names(block))) {
    cli::cli_abort(c(
      "{.field schema.value_maps} must be a block keyed by canonical column.",
      "i" = "For example {.code value_maps: {{trip_status: {{\"1\": complete}}}}}."
    ))
  }
  lapply(block, function(entry) {
    if (!is.list(entry) && !is.character(entry)) {
      cli::cli_abort(
        "Each {.field schema.value_maps} entry must map source codes to canonical values."
      )
    }
    stats::setNames(as.character(unlist(entry, use.names = FALSE)), as.character(names(entry)))
  })
}

# Internal: turn the YAML `strata_cols` block into the named character vector
# creel_schema() expects.
#
# Both YAML shapes are accepted, matching the two the argument itself takes:
# a mapping (`day_type: DayType`) when the source column is named differently,
# and a bare sequence (`- day_type`) when the source already uses the design's
# name. A sequence parses to an unnamed list, which normalize_strata_cols()
# then reads as naming itself on both sides.
#' @noRd
.yaml_strata_cols <- function(block) {
  if (!is.list(block) && !is.character(block)) {
    cli::cli_abort(c(
      "{.field schema.strata_cols} must be a mapping or a sequence.",
      "i" = paste0(
        "Use {.code strata_cols: {{day_type: DayType}}} to rename, or ",
        "{.code strata_cols: [day_type]} when the source already uses the ",
        "design's name."
      )
    ))
  }
  flat <- unlist(block, use.names = TRUE)
  if (!is.character(flat)) {
    flat <- as.character(flat)
    names(flat) <- names(unlist(block, use.names = TRUE))
  }
  flat
}

# Internal: turn the YAML `columns` block into the `<canonical>_col` arguments
# creel_schema() expects.
#
# Keys are canonical tidycreel names without the `_col` suffix, matching the way
# `value_maps` is keyed by canonical column: `date: SurveyDate` rather than
# `date_col: SurveyDate`. The accepted set is read off creel_schema() itself so
# the two cannot drift apart.
#' @noRd
.yaml_schema_columns <- function(block) {
  if (!is.list(block) && !is.character(block)) {
    cli::cli_abort(c(
      "{.field schema.columns} must be a mapping of canonical name to source column.",
      "i" = "For example {.code columns: {{date: SurveyDate}}}."
    ))
  }
  flat <- unlist(block, use.names = TRUE)
  if (length(flat) == 0L || is.null(names(flat)) || !all(nzchar(names(flat)))) {
    cli::cli_abort(c(
      "Every {.field schema.columns} entry must name the canonical column it maps.",
      "i" = "For example {.code columns: {{date: SurveyDate}}}."
    ))
  }
  flat <- stats::setNames(as.character(flat), names(flat))

  known <- sub("_col$", "", grep("_col$", names(formals(tidycreel::creel_schema)), value = TRUE))
  suffixed <- names(flat)[sub("_col$", "", names(flat)) %in% known & grepl("_col$", names(flat))]
  if (length(suffixed) > 0L) {
    cli::cli_abort(c(
      "{.field schema.columns} key{?s} carr{?ies/y} a {.code _col} suffix: {.field {suffixed}}",
      "i" = "Drop the suffix -- the block is keyed by canonical name, as in \\
             {.code columns: {{date: SurveyDate}}}."
    ))
  }
  unknown <- setdiff(names(flat), known)
  if (length(unknown) > 0L) {
    cli::cli_abort(c(
      "Unknown {.field schema.columns} key{?s}: {.field {unknown}}",
      "i" = "Keys are canonical tidycreel column names: {.val {known}}"
    ))
  }
  stats::setNames(as.list(flat), paste0(names(flat), "_col"))
}
