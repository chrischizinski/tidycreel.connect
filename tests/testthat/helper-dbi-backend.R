# Helper: an in-memory duckdb carrying exactly the rows make_test_csv() writes.
#
# The point of matching them row for row is the parity test: the CSV and DBI
# backends share every stage after the read, so the same source data must come
# back identical from both. A fixture that differed would let the two drift
# while both still "passed".

make_dbi_test_tables <- function() {
  list(
    interviews = data.frame(
      interview_uid = 1L:2L,
      date = as.Date(c("2024-06-01", "2024-06-02")),
      catch_count = c(3L, 0L),
      effort_hours = c(2.5, 1.0),
      trip_status = c("complete", "incomplete"),
      stringsAsFactors = FALSE
    ),
    counts = data.frame(
      date = as.Date(c("2024-06-01", "2024-06-02")),
      bank_anglers  = c(12L, 8L),
      angler_boats  = c(0L, 0L),
      non_ang_boats = c(0L, 0L),
      stringsAsFactors = FALSE
    ),
    # Written as a genuine TIME column by make_dbi_conn(), so the count-time
    # path is exercised on the type a database actually returns rather than on
    # a string that never leaves R.
    counts_timed = data.frame(
      date = as.Date(c("2024-06-01", "2024-06-01")),
      count_time = as.difftime(c(59400, 34200), units = "secs"),
      bank_anglers  = c(12L, 8L),
      angler_boats  = c(0L, 0L),
      non_ang_boats = c(0L, 0L),
      stringsAsFactors = FALSE
    ),
    catch = data.frame(
      catch_uid = 1L:2L,
      interview_uid = c(1L, 1L),
      species = c("walleye", "walleye"),
      catch_count = c(2L, 1L),
      catch_type = c("harvest", "release"),
      stringsAsFactors = FALSE
    ),
    harvest_lengths = data.frame(
      length_uid = 1L,
      interview_uid = 1L,
      species = "walleye",
      length_mm = 450.0,
      length_type = "harvest",
      stringsAsFactors = FALSE
    ),
    release_lengths = data.frame(
      length_uid = 2L,
      interview_uid = 1L,
      species = "walleye",
      length_mm = 380.5,
      length_type = "release",
      stringsAsFactors = FALSE
    )
  )
}

#' Open an in-memory duckdb holding the fixture tables.
#'
#' `tables` is a named list; each element is written under its own name. A test
#' that wants a different table name passes a differently named list, which is
#' what DBI-BACKEND-07 does for the single `lengths` table.
#'
#' There was a `names_map` argument here for renaming on the way in. Nothing
#' used it, and it called `%||%`, which base R only supplies from 4.4 while
#' this package declares R (>= 4.1.0) -- so the one branch no test exercised
#' was also the one that would have failed for part of the supported range.
make_dbi_conn <- function(tables = make_dbi_test_tables()) {
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    testthat::skip("duckdb not installed")
  }
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE), envir = parent.frame())
  for (nm in names(tables)) {
    DBI::dbWriteTable(con, nm, tables[[nm]])
  }
  con
}

#' The schema make_test_schema() gives, plus the table names a DBI read needs.
make_dbi_schema <- function(...) {
  args <- list(
    survey_type       = "instantaneous",
    interview_uid_col = "interview_uid",
    date_col          = "date",
    catch_col         = "catch_count",
    effort_col        = "effort_hours",
    trip_status_col   = "trip_status",
    bank_anglers_col  = "bank_anglers",
    angler_boats_col  = "angler_boats",
    non_ang_boats_col = "non_ang_boats",
    catch_uid_col     = "catch_uid",
    species_col       = "species",
    catch_count_col   = "catch_count",
    catch_type_col    = "catch_type",
    length_uid_col    = "length_uid",
    length_mm_col     = "length_mm",
    length_type_col   = "length_type",
    interviews_table      = "interviews",
    counts_table          = "counts",
    catch_table           = "catch",
    harvest_lengths_table = "harvest_lengths",
    release_lengths_table = "release_lengths"
  )
  overrides <- list(...)
  for (nm in names(overrides)) args[[nm]] <- overrides[[nm]]
  do.call(tidycreel::creel_schema, args)
}
