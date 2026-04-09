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
  # Load all keys at once — use_parent=FALSE prevents searching parent directories
  cfg <- config::get(value = NULL, config = config, file = path, use_parent = FALSE)
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
      "i" = "Add {.code backend: csv} or {.code backend: sqlserver} to your config."
    ))
  }
  backend <- cfg$backend

  # 2. Validate backend value
  valid_backends <- c("csv", "sqlserver")
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
    # Validate credentials are non-empty (Pitfall 2: !expr returns "" for unset env vars)
    cred_fields <- c("username", "password")
    empty_creds <- cred_fields[vapply(cred_fields, function(k) {
      val <- cfg[[k]]
      !is.null(val) && !nzchar(val)
    }, logical(1))]
    if (length(empty_creds) > 0L) {
      cli::cli_abort(c(
        "Credential field{?s} resolved to empty string in YAML config: {.file {path}}",
        stats::setNames(
          paste0("{.field ", empty_creds, "} — check that the environment variable is set"),
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

  # Build a minimal creel_schema from the YAML schema block
  # Column mappings are not in YAML — this schema holds table names only
  schema_args <- list(survey_type = survey_type)
  table_keys <- c(
    "interviews_table", "counts_table", "catch_table",
    "harvest_lengths_table", "release_lengths_table"
  )
  for (k in table_keys) {
    if (!is.null(cfg$schema[[k]])) schema_args[[k]] <- cfg$schema[[k]]
  }
  schema <- do.call(tidycreel::creel_schema, schema_args)

  if (backend == "csv") {
    paths <- as.list(cfg$files)
    .creel_connect_csv(paths, schema) # nolint: object_usage_linter
  } else if (backend == "sqlserver") {
    if (!requireNamespace("odbc", quietly = TRUE)) {
      cli::cli_abort(c(
        "Package {.pkg odbc} is required for SQL Server connections.",
        "i" = "Install it with {.code install.packages('odbc')}."
      ))
    }
    dbi_con <- DBI::dbConnect(
      odbc::odbc(),
      Driver   = "ODBC Driver 17 for SQL Server",
      Server   = cfg$server,
      Database = cfg$database,
      UID      = cfg$username,
      PWD      = cfg$password
    )
    .creel_connect_dbi(dbi_con, schema) # nolint: object_usage_linter
  }
}
