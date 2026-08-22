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
  .build_creel_conn(cfg)
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
      api_field_map = lapply(as.list(cfg$field_map), as.list)
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
