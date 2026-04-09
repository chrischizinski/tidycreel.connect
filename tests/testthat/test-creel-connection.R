# Tests for creel_connect() — CONNECT-01 (DBI), CONNECT-02 (CSV), CONNECT-05 (print)

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

# CONNECT-01: DBI backend
test_that("creel_connect() with DBIConnection returns creel_connection with backend='dbi'", {
  skip_if_not_installed("duckdb")
  db_con <- make_test_db()
  on.exit(DBI::dbDisconnect(db_con))
  conn <- creel_connect(db_con, schema_inst())
  expect_s3_class(conn, "creel_connection")
  expect_equal(conn$backend, "dbi")
})

test_that("creel_connect() with DBIConnection stores schema by value", {
  skip_if_not_installed("duckdb")
  db_con <- make_test_db()
  on.exit(DBI::dbDisconnect(db_con))
  conn <- creel_connect(db_con, schema_inst())
  expect_s3_class(conn$schema, "creel_schema")
})

test_that("creel_connect() rejects non-DBIConnection non-list con with cli_abort()", {
  expect_error(creel_connect("not_a_connection", schema_inst()), class = "rlang_error")
})

test_that("creel_connect() rejects invalid schema argument", {
  skip_if_not_installed("duckdb")
  db_con <- make_test_db()
  on.exit(DBI::dbDisconnect(db_con))
  expect_error(creel_connect(db_con, list(survey_type = "instantaneous")), class = "rlang_error")
})

# CONNECT-02: CSV backend
test_that("creel_connect() with named list of paths returns creel_connection with backend='csv'", {
  skip_if_not_installed("withr")
  paths <- make_test_csv()
  conn <- creel_connect(paths, schema_inst())
  expect_s3_class(conn, "creel_connection")
  expect_equal(conn$backend, "csv")
})

test_that("creel_connect() CSV backend aborts with cli_abort() if any file missing", {
  bad_paths <- list(
    interviews = "/nonexistent/interviews.csv",
    counts = "/nonexistent/counts.csv",
    catch = "/nonexistent/catch.csv",
    harvest_lengths = "/nonexistent/harvest_lengths.csv",
    release_lengths = "/nonexistent/release_lengths.csv"
  )
  expect_error(creel_connect(bad_paths, schema_inst()), class = "rlang_error")
})

test_that("creel_connect() CSV backend stores status = 'ready'", {
  skip_if_not_installed("withr")
  paths <- make_test_csv()
  conn <- creel_connect(paths, schema_inst())
  expect_equal(conn$status, "ready")
})

# CONNECT-05: print
test_that("print.creel_connection() output contains backend type", {
  skip_if_not_installed("withr")
  paths <- make_test_csv()
  conn <- creel_connect(paths, schema_inst())
  out <- capture.output(print(conn))
  expect_true(any(grepl("csv", out, ignore.case = TRUE)))
})

test_that("print.creel_connection() output contains 'Status'", {
  skip_if_not_installed("withr")
  paths <- make_test_csv()
  conn <- creel_connect(paths, schema_inst())
  out <- capture.output(print(conn))
  expect_true(any(grepl("Status", out)))
})

test_that("print.creel_connection() invisibly returns x", {
  skip_if_not_installed("withr")
  paths <- make_test_csv()
  conn <- creel_connect(paths, schema_inst())
  expect_invisible(print(conn))
})
