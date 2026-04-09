# Helper: in-memory DuckDB fixture for creel schema tests
# Phase 66: creel_schema S3 Class
#
# make_test_db() creates an in-memory DuckDB database with representative
# creel tables (interviews, counts, catch, lengths). Any test that calls
# make_test_db() must guard with skip_if_not_installed("duckdb") first.

make_test_db <- function() {
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    testthat::skip("duckdb not installed")
  }

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")

  interviews <- data.frame(
    date = as.Date(c("2024-06-01", "2024-06-02", "2024-06-03")),
    catch_count = c(3L, 0L, 5L),
    effort_hours = c(2.5, 1.0, 4.0),
    trip_status = c("complete", "incomplete", "complete"),
    stringsAsFactors = FALSE
  )

  counts <- data.frame(
    date = as.Date(c("2024-06-01", "2024-06-02", "2024-06-03")),
    angler_count = c(12L, 8L, 20L),
    stringsAsFactors = FALSE
  )

  catch <- data.frame(
    catch_uid = 1L:5L,
    interview_uid = c(1L, 1L, 3L, 3L, 3L),
    species = c("walleye", "walleye", "bass", "bass", "walleye"),
    catch_count = c(2L, 1L, 3L, 1L, 1L),
    catch_type = c("harvest", "release", "harvest", "release", "harvest"),
    stringsAsFactors = FALSE
  )

  lengths <- data.frame(
    length_uid = 1L:4L,
    interview_uid = c(1L, 1L, 3L, 3L),
    species = c("walleye", "walleye", "bass", "bass"),
    length_mm = c(450.0, 380.5, 320.0, 295.0),
    length_type = c("harvest", "release", "harvest", "release"),
    stringsAsFactors = FALSE
  )

  DBI::dbWriteTable(con, "interviews", interviews)
  DBI::dbWriteTable(con, "counts", counts)
  DBI::dbWriteTable(con, "catch", catch)
  DBI::dbWriteTable(con, "lengths", lengths)

  con
}
