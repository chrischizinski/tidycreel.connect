# Tests for creel_connect_from_yaml() — CONNECT-03 (YAML connect), CONNECT-04 (credentials)

schema_inst <- function() {
  tidycreel::creel_schema(
    survey_type = "instantaneous",
    interviews_table = "interviews",
    counts_table = "counts",
    catch_table = "catch",
    date_col = "date",
    catch_col = "catch_count",
    effort_col = "effort_hours",
    trip_status_col = "trip_status",
    count_col = "angler_count",
    catch_uid_col = "catch_uid",
    interview_uid_col = "interview_uid",
    species_col = "species",
    catch_count_col = "catch_count",
    catch_type_col = "catch_type",
    length_uid_col = "length_uid",
    length_mm_col = "length_mm",
    length_type_col = "length_type"
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
