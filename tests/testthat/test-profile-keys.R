# A profile key nothing reads is refused, not ignored (#40).
#
# Ignored keys let a profile load while doing less than it said. The docs
# showed `auth_type:` (read by no code) and `*_col` keys under `schema:`
# (ignored), and every copied profile loaded "successfully"; a typo such as
# `field_mpa:` or `interviews_tabel:` fell back to a default the same way.
# These tests pin that each such key stops the load and is named, before any
# connection is attempted.

profile_file <- function(lines, envir = parent.frame()) {
  path <- withr::local_tempfile(fileext = ".yml", .local_envir = envir)
  writeLines(lines, path)
  path
}

csv_profile_lines <- function(extra = character(), schema_extra = character()) {
  c(
    "default:",
    "  backend: csv",
    "  files:",
    "    interviews: interviews.csv",
    "    counts: counts.csv",
    "    catch: catch.csv",
    "    harvest_lengths: harvest.csv",
    "    release_lengths: release.csv",
    paste0("  ", extra),
    "  schema:",
    "    survey_type: instantaneous",
    paste0("    ", schema_extra)
  )
}

test_that("an unknown top-level key aborts, naming it", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  err <- expect_error(
    creel_connect_from_yaml(profile_file(csv_profile_lines("auth_type: password"))),
    class = "creel_error_profile_unknown_key"
  )
  expect_match(conditionMessage(err), "auth_type")
  # The valid keys are listed, so the fix is in the message.
  expect_match(conditionMessage(err), "files")
})

test_that("a typo in an API key is refused, not left to a default", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  path <- profile_file(c(
    "default:",
    "  backend: api",
    '  base_url: "https://api.example.org/creel/"',
    '  uid_param: "survey_id"',
    "  creel_uids:",
    '    - "s-1"',
    "  schema:",
    "    survey_type: instantaneous",
    "  endpoints:",
    '    interviews: "v2/interviews"',
    "  field_map:",
    "    interviews:",
    '      interview_uid: "InterviewID"',
    "  pagnation:",
    "    style: link"
  ))
  err <- expect_error(
    creel_connect_from_yaml(path),
    class = "creel_error_profile_unknown_key"
  )
  # Ignored, the misspelt block meant "no pagination": one page returned.
  expect_match(conditionMessage(err), "pagnation")
})

test_that("a key another backend reads says which backend", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  err <- expect_error(
    creel_connect_from_yaml(profile_file(csv_profile_lines("server: db.example.org"))),
    class = "creel_error_profile_unknown_key"
  )
  expect_match(conditionMessage(err), "backend: sqlserver")
})

test_that("an unknown schema key aborts; a _col key is pointed at columns:", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  err <- expect_error(
    creel_connect_from_yaml(profile_file(
      csv_profile_lines(schema_extra = "date_col: SurveyDate")
    )),
    class = "creel_error_profile_unknown_key"
  )
  expect_match(conditionMessage(err), "date_col")
  expect_match(conditionMessage(err), "columns:")

  expect_error(
    creel_connect_from_yaml(profile_file(
      csv_profile_lines(schema_extra = "interviews_tabel: vwInterviews")
    )),
    class = "creel_error_profile_unknown_key"
  )
})

test_that("config's own inherits key is accepted", {
  # config keeps `inherits:` in the list it returns for a block that
  # inherits another (checked with config 0.3.2), so refusing it would break
  # every multi-environment profile.
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  lines <- csv_profile_lines()
  path <- profile_file(c(lines, "other:", "  inherits: default"))
  expect_no_error(
    tryCatch(
      creel_connect_from_yaml(path, config = "other"),
      # The CSV files do not exist; anything after key validation is fine.
      error = function(e) {
        if (inherits(e, "creel_error_profile_unknown_key")) stop(e)
        NULL
      }
    )
  )
})

test_that("lengths_table alone reaches both length tables", {
  # creel_schema() falls back to `lengths_table` for harvest and release;
  # before #40 the profile route never passed it on, so neither was set.
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  skip_if_not_installed("odbc")
  skip_if_not_installed("duckdb")
  real_connect <- DBI::dbConnect
  local_mocked_bindings(
    dbConnect = function(drv, ...) real_connect(duckdb::duckdb()),
    .package = "DBI"
  )
  conn <- creel_connect_from_yaml(profile_file(c(
    "default:",
    "  backend: sqlserver",
    "  server: db.example.org",
    "  database: CreelDB",
    "  username: reader",
    "  password: not-a-secret",
    "  schema:",
    "    survey_type: instantaneous",
    "    lengths_table: vwLengths"
  )))
  on.exit(DBI::dbDisconnect(conn$con, shutdown = TRUE), add = TRUE)
  expect_identical(conn$schema$harvest_lengths_table, "vwLengths")
  expect_identical(conn$schema$release_lengths_table, "vwLengths")
})
