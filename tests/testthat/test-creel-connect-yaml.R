# Tests for creel_connect_from_yaml() — CONNECT-03 (YAML connect), CONNECT-04 (credentials)

schema_inst <- function() {
  tidycreel::creel_schema(
    survey_type       = "instantaneous",
    interviews_table  = "interviews",
    counts_table      = "counts",
    catch_table       = "catch",
    date_col          = "date",
    catch_col         = "catch_count",
    effort_col        = "effort_hours",
    trip_status_col   = "trip_status",
    bank_anglers_col  = "bank_anglers",
    angler_boats_col  = "angler_boats",
    non_ang_boats_col = "non_ang_boats",
    catch_uid_col     = "catch_uid",
    interview_uid_col = "interview_uid",
    species_col       = "species",
    catch_count_col   = "catch_count",
    catch_type_col    = "catch_type",
    length_uid_col    = "length_uid",
    length_mm_col     = "length_mm",
    length_type_col   = "length_type"
  )
}

make_csv_yaml <- function(paths) {
  # Write a valid CSV YAML config referencing `paths` (named list)
  # Returns path to temp YAML file
  # .local_envir = parent.frame() binds temp file lifetime to the calling test block
  yaml_path <- withr::local_tempfile(fileext = ".yml", .local_envir = parent.frame())
  writeLines(c(
    "default:",
    "  backend: csv",
    "  files:",
    paste0("    interviews: ", paths$interviews),
    paste0("    counts: ", paths$counts),
    paste0("    catch: ", paths$catch),
    paste0("    harvest_lengths: ", paths$harvest_lengths),
    paste0("    release_lengths: ", paths$release_lengths),
    "  schema:",
    "    survey_type: instantaneous"
  ), yaml_path)
  yaml_path
}

# CONNECT-03: YAML-based connection
test_that("creel_connect_from_yaml() with valid CSV YAML returns creel_connection", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  paths <- make_test_csv()
  yaml_path <- make_csv_yaml(paths)
  conn <- creel_connect_from_yaml(yaml_path)
  expect_s3_class(conn, "creel_connection")
})

test_that("creel_connect_from_yaml() aborts if path does not exist", {
  skip_if_not_installed("config")
  expect_error(
    creel_connect_from_yaml("/nonexistent/config.yml"),
    class = "rlang_error"
  )
})

test_that("creel_connect_from_yaml() aborts before connection if required YAML key missing", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  yaml_path <- withr::local_tempfile(fileext = ".yml")
  # Missing 'files' key entirely
  writeLines(c(
    "default:",
    "  backend: csv",
    "  schema:",
    "    survey_type: instantaneous"
  ), yaml_path)
  expect_error(creel_connect_from_yaml(yaml_path), class = "rlang_error")
})

test_that("creel_connect_from_yaml() aborts if csv backend has missing file", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  yaml_path <- withr::local_tempfile(fileext = ".yml")
  writeLines(c(
    "default:",
    "  backend: csv",
    "  files:",
    "    interviews: /nonexistent/interviews.csv",
    "    counts: /nonexistent/counts.csv",
    "    catch: /nonexistent/catch.csv",
    "    harvest_lengths: /nonexistent/harvest_lengths.csv",
    "    release_lengths: /nonexistent/release_lengths.csv",
    "  schema:",
    "    survey_type: instantaneous"
  ), yaml_path)
  expect_error(creel_connect_from_yaml(yaml_path), class = "rlang_error")
})

test_that("creel_connect_from_yaml() config argument selects environment block", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  paths <- make_test_csv()
  yaml_path <- withr::local_tempfile(fileext = ".yml")
  writeLines(c(
    "default:",
    "  backend: csv",
    "  files:",
    paste0("    interviews: ", paths$interviews),
    paste0("    counts: ", paths$counts),
    paste0("    catch: ", paths$catch),
    paste0("    harvest_lengths: ", paths$harvest_lengths),
    paste0("    release_lengths: ", paths$release_lengths),
    "  schema:",
    "    survey_type: instantaneous",
    "staging:",
    "  backend: csv",
    "  files:",
    paste0("    interviews: ", paths$interviews),
    paste0("    counts: ", paths$counts),
    paste0("    catch: ", paths$catch),
    paste0("    harvest_lengths: ", paths$harvest_lengths),
    paste0("    release_lengths: ", paths$release_lengths),
    "  schema:",
    "    survey_type: instantaneous"
  ), yaml_path)
  conn <- creel_connect_from_yaml(yaml_path, config = "staging")
  expect_s3_class(conn, "creel_connection")
})

# CONNECT-04: credentials via !expr Sys.getenv()
test_that("creel_connect_from_yaml() reads credentials from env vars via !expr", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  paths <- make_test_csv()
  yaml_path <- withr::local_tempfile(fileext = ".yml")
  # Use !expr to inject an env var value (here reusing CSV backend to avoid needing real DB)
  # We verify the YAML key is evaluated (env var injected) not stored as literal !expr string
  writeLines(c(
    "default:",
    "  backend: csv",
    "  files:",
    paste0("    interviews: !expr Sys.getenv('TC_INTERVIEWS_PATH')"),
    paste0("    counts: ", paths$counts),
    paste0("    catch: ", paths$catch),
    paste0("    harvest_lengths: ", paths$harvest_lengths),
    paste0("    release_lengths: ", paths$release_lengths),
    "  schema:",
    "    survey_type: instantaneous"
  ), yaml_path)
  # With env var set, path resolves correctly
  withr::with_envvar(
    list(TC_INTERVIEWS_PATH = paths$interviews),
    {
      conn <- creel_connect_from_yaml(yaml_path)
      expect_s3_class(conn, "creel_connection")
    }
  )
})

# --- backend: api -------------------------------------------------------------
#
# These call the internals directly rather than creel_connect_from_yaml(), so
# they run without the {config} package: what is under test is the api branch of
# the validator and the builder, not config's file reading.

test_that("the shipped template profile builds a working api connection", {
  skip_if_not_installed("yaml")
  path <- system.file("extdata", "api-profile-example.yml", package = "tidycreel.connect")
  skip_if(!nzchar(path))
  cfg <- yaml::read_yaml(path)$default

  expect_silent(tidycreel.connect:::.validate_yaml_config(cfg, path))
  conn <- tidycreel.connect:::.build_creel_conn(cfg)

  expect_s3_class(conn, "creel_connection_api")
  expect_equal(conn$con$uid_param, "survey_id")
  expect_equal(conn$con$endpoints$interviews, "v2/interviews")
  # The template is what a user copies, so the optional interview fields have to
  # be in it -- an example that omits the party size teaches the party-hours bug.
  expect_equal(conn$con$api_field_map$interviews$n_anglers, "PartySize")
})

test_that("an api profile missing part of the contract is refused", {
  # The API contract lives in the profile because it lives nowhere else: a
  # profile without it would produce a connection that decodes nothing.
  cfg <- list(
    backend  = "api",
    base_url = "https://api.example.org/creel/",
    schema   = list(survey_type = "instantaneous")
  )
  expect_error(
    tidycreel.connect:::.validate_yaml_config(cfg, "test.yml"),
    "uid_param|creel_uids|endpoints|field_map"
  )
})

test_that("the api profile error points at the template", {
  cfg <- list(
    backend = "api",
    schema  = list(survey_type = "instantaneous")
  )
  expect_error(
    tidycreel.connect:::.validate_yaml_config(cfg, "test.yml"),
    "api-profile-example"
  )
})


## strata_cols and value_maps through a profile (GH #171, #128) ----------------

test_that("a profile can declare strata_cols and value_maps", {
  # The loader carried only survey_type and table names, so neither field could
  # be declared by the route the docs recommend: a profile-configured survey
  # could not be stratified, and a coded source could not be translated. Both
  # describe the source rather than one backend, so both belong in the profile
  # alongside the field map.
  skip_if_not_installed("config")
  skip_if_not_installed("withr")

  yaml_path <- withr::local_tempfile(fileext = ".yml")
  writeLines(c(
    "default:",
    "  backend: api",
    '  base_url: "https://api.example.org/creel/"',
    '  uid_param: "survey_id"',
    "  creel_uids:",
    '    - "s-1"',
    "  schema:",
    "    survey_type: instantaneous",
    "    strata_cols:",
    '      day_type: "DayTypeCode"',
    "    value_maps:",
    "      trip_status:",
    '        "1": complete',
    '        "2": incomplete',
    "  endpoints:",
    '    interviews: "v2/interviews"',
    "  field_map:",
    "    interviews:",
    '      interview_uid: "InterviewID"',
    '      date: "SurveyDate"',
    '      trip_status: "TripStatus"',
    '      effort_hours: "HoursFished"'
  ), yaml_path)

  conn <- creel_connect_from_yaml(yaml_path)

  # Reached the schema in the shape creel_schema() stores, not merely present.
  expect_equal(conn$schema$strata_cols, c(day_type = "DayTypeCode"))
  expect_equal(
    conn$schema$value_maps$trip_status,
    c("1" = "complete", "2" = "incomplete")
  )
})

test_that("a profile's declarations actually reach a fetch", {
  # The point is the fetched frame, not the schema object: a field that is
  # stored but never read looks identical at this seam.
  skip_if_not_installed("config")
  skip_if_not_installed("withr")

  yaml_path <- withr::local_tempfile(fileext = ".yml")
  writeLines(c(
    "default:",
    "  backend: api",
    '  base_url: "https://api.example.org/creel/"',
    '  uid_param: "survey_id"',
    "  creel_uids:",
    '    - "s-1"',
    "  schema:",
    "    survey_type: instantaneous",
    "    strata_cols:",
    '      day_type: "DayTypeCode"',
    "    value_maps:",
    "      trip_status:",
    '        "1": complete',
    '        "2": incomplete',
    "  endpoints:",
    '    interviews: "v2/interviews"',
    "  field_map:",
    "    interviews:",
    '      interview_uid: "InterviewID"',
    '      date: "SurveyDate"',
    '      trip_status: "TripStatus"',
    '      effort_hours: "HoursFished"',
    "      day_type: \"DayTypeCode\""
  ), yaml_path)

  conn <- creel_connect_from_yaml(yaml_path)
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body = charToRaw(paste0(
        '[{"InterviewID":1,"SurveyDate":"2024-06-01","TripStatus":"1",',
        '"HoursFished":2.5,"DayTypeCode":"weekday"},',
        '{"InterviewID":2,"SurveyDate":"2024-06-02","TripStatus":"2",',
        '"HoursFished":1.0,"DayTypeCode":"weekend"}]'
      ))
    )
  })

  iv <- suppressMessages(fetch_interviews(conn))

  # Codes translated, stratum carried under the design-facing name.
  expect_equal(iv$trip_status, c("complete", "incomplete"))
  expect_equal(iv$day_type, c("weekday", "weekend"))
})
