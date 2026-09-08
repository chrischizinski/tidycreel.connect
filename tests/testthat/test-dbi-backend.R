# Tests for GH #185: the DBI backend actually loads data.
#
# WHY these tests exist
#
# The backend opened a real connection and reported itself open, while every
# fetch_*() off it aborted as unimplemented. test-sqlserver-not-implemented.R
# pinned those aborts so that implementing them would fail and prompt the docs
# to be corrected in the same change; this file replaces it.
#
# The load is only ever one stage: read the named table. Rename, coercion,
# value maps and validation are shared with the CSV backend and untouched. The
# parity tests below are the ones that matter, because they are what would fail
# if the DBI path ever grew its own copy of a stage the CSV path already owns.

skip_if_no_duckdb <- function() {
  testthat::skip_if_not_installed("duckdb")
}

# ---- parity with the CSV backend --------------------------------------------

test_that("DBI-BACKEND-01: every fetch returns what CSV returns from the same rows", {
  skip_if_no_duckdb()
  con <- make_dbi_conn()
  dbi_conn <- creel_connect(con, make_dbi_schema())
  csv_conn <- creel_connect(make_test_csv(), make_test_schema())

  fetchers <- list(
    fetch_interviews      = fetch_interviews,
    fetch_counts          = fetch_counts,
    fetch_catch           = fetch_catch,
    fetch_harvest_lengths = fetch_harvest_lengths,
    fetch_release_lengths = fetch_release_lengths
  )
  for (nm in names(fetchers)) {
    from_dbi <- suppressMessages(fetchers[[nm]](dbi_conn))
    from_csv <- suppressMessages(fetchers[[nm]](csv_conn))
    # as.data.frame on both sides: readr hands back a tibble and DBI a plain
    # frame, which is a container difference rather than a data one.
    expect_equal(
      as.data.frame(from_dbi),
      as.data.frame(from_csv),
      info = nm
    )
  }
})

test_that("DBI-BACKEND-02: interviews come back with canonical names and types", {
  skip_if_no_duckdb()
  conn <- creel_connect(make_dbi_conn(), make_dbi_schema())
  df <- suppressMessages(fetch_interviews(conn))

  expect_true(all(c("interview_uid", "date", "catch_count", "effort", "trip_status") %in% names(df)))
  # The source column is `effort_hours`; the schema maps it. A frame that came
  # back still carrying the source name would mean the rename never ran.
  expect_false("effort_hours" %in% names(df))
  expect_s3_class(df$date, "Date")
  expect_type(df$effort, "double")
  expect_equal(nrow(df), 2L)
})

test_that("DBI-BACKEND-03: the schema selects columns, exactly as it does for CSV", {
  skip_if_no_duckdb()
  # An unmapped source column is dropped rather than carried, which is the
  # behaviour #126 established and the reason a fetch reports what it dropped.
  tables <- make_dbi_test_tables()
  tables$interviews$comment <- c("windy", "calm")
  conn <- creel_connect(make_dbi_conn(tables), make_dbi_schema())
  df <- suppressMessages(fetch_interviews(conn))
  expect_false("comment" %in% names(df))
})

# ---- table names ------------------------------------------------------------

test_that("DBI-BACKEND-04: a table the schema does not name is refused by name", {
  skip_if_no_duckdb()
  # There is no canonical table name the way there is a canonical column name,
  # so an unnamed table cannot be guessed at. The error has to say which
  # setting is missing, or the caller is left guessing which of five it was.
  conn <- creel_connect(
    make_dbi_conn(),
    make_dbi_schema(interviews_table = NULL)
  )
  expect_error(
    fetch_interviews(conn),
    class = "creel_error_no_table_name"
  )
  expect_error(fetch_interviews(conn), "interviews_table")
})

test_that("DBI-BACKEND-05: a named table the database lacks is refused as missing", {
  skip_if_no_duckdb()
  # Distinct from -04 on purpose: "you did not configure this" and "you
  # configured a name that is not there" are different mistakes, and a shared
  # message would send the caller to the wrong one.
  conn <- creel_connect(
    make_dbi_conn(),
    make_dbi_schema(interviews_table = "vwInterviews")
  )
  expect_error(
    fetch_interviews(conn),
    class = "creel_error_table_not_found"
  )
  expect_error(fetch_interviews(conn), "vwInterviews")
})

test_that("DBI-BACKEND-06: harvest and release lengths read their own tables", {
  skip_if_no_duckdb()
  conn <- creel_connect(make_dbi_conn(), make_dbi_schema())
  harvest <- suppressMessages(fetch_harvest_lengths(conn))
  release <- suppressMessages(fetch_release_lengths(conn))
  # Different tables, so different rows. Reading one table for both would give
  # two identical frames and still look like it worked.
  expect_equal(harvest$length_mm, 450.0)
  expect_equal(release$length_mm, 380.5)
  expect_false(identical(harvest, release))
})

test_that("DBI-BACKEND-07: lengths_table serves both when neither is named", {
  skip_if_no_duckdb()
  # A source keeping one lengths table needs no new setting: creel_schema()
  # falls both specific names back to `lengths_table`.
  tables <- make_dbi_test_tables()
  both <- rbind(tables$harvest_lengths, tables$release_lengths)
  conn <- creel_connect(
    make_dbi_conn(list(lengths = both)),
    make_dbi_schema(
      harvest_lengths_table = NULL,
      release_lengths_table = NULL,
      lengths_table = "lengths"
    )
  )
  expect_equal(nrow(suppressMessages(fetch_harvest_lengths(conn))), 2L)
  expect_equal(nrow(suppressMessages(fetch_release_lengths(conn))), 2L)
})

test_that("DBI-BACKEND-11: a TIME column comes back as a clock label, not seconds", {
  skip_if_no_duckdb()
  # The CSV reader keeps a count time as text by forcing the column to
  # character before readr parses it (GH #129). A database gives no such
  # chance: duckdb returns TIME as difftime, where as.character() yields the
  # seconds since midnight. .coerce_count_time() is as.character(), so without
  # a render step the frame would carry "59400" where the source wrote 16:30 --
  # not a mangled label but a different quantity, accepted silently.
  conn <- creel_connect(
    make_dbi_conn(),
    make_dbi_schema(counts_table = "counts_timed", count_time_col = "count_time")
  )
  df <- suppressMessages(fetch_counts(conn))

  expect_type(df$count_time, "character")
  expect_equal(sort(df$count_time), c("09:30", "16:30"))
  # The failure this guards is specific and would otherwise look plausible.
  expect_false(any(grepl("^[0-9]{4,}$", df$count_time)))
})

test_that("DBI-BACKEND-12: a non-zero seconds time keeps its seconds", {
  skip_if_no_duckdb()
  # Rendering to "HH:MM" must not round a real value away. Seconds appear only
  # when they are not zero, so a whole-minute time reads as the source wrote it
  # and a 16:30:45 count keeps its 45.
  tables <- make_dbi_test_tables()
  tables$counts_timed$count_time <- as.difftime(c(59445, 34200), units = "secs")
  conn <- creel_connect(
    make_dbi_conn(tables),
    make_dbi_schema(counts_table = "counts_timed", count_time_col = "count_time")
  )
  df <- suppressMessages(fetch_counts(conn))
  expect_true("16:30:45" %in% df$count_time)
  expect_true("09:30" %in% df$count_time)
})

test_that("DBI-BACKEND-15: a schema-qualified DBI::Id names a table", {
  skip_if_no_duckdb()
  # The only way to reach a qualified table: dbExistsTable() finds
  # Id(schema = "dbo", table = "t") where the string "dbo.t" returns FALSE.
  # SQL Server tables are routinely qualified, so a guard demanding a character
  # scalar put the backend's main case out of reach -- and called it "not set",
  # which is not what had gone wrong.
  con <- make_dbi_conn(list())
  DBI::dbExecute(con, "CREATE SCHEMA dbo")
  DBI::dbWriteTable(
    con,
    DBI::Id(schema = "dbo", table = "interviews"),
    make_dbi_test_tables()$interviews
  )
  conn <- creel_connect(
    con,
    make_dbi_schema(interviews_table = DBI::Id(schema = "dbo", table = "interviews"))
  )
  df <- suppressMessages(fetch_interviews(conn))
  expect_equal(nrow(df), 2L)
  expect_true("interview_uid" %in% names(df))
})

test_that("DBI-BACKEND-16: a missing qualified table is reported by its full name", {
  skip_if_no_duckdb()
  # An Id has no useful character form, so the message renders it. Reporting
  # "vwInterviews" for a table configured as dbo.vwInterviews would send the
  # reader looking in the wrong schema.
  con <- make_dbi_conn(list())
  DBI::dbExecute(con, "CREATE SCHEMA dbo")
  conn <- creel_connect(
    con,
    make_dbi_schema(interviews_table = DBI::Id(schema = "dbo", table = "vwInterviews"))
  )
  expect_error(fetch_interviews(conn), class = "creel_error_table_not_found")
  expect_error(fetch_interviews(conn), "dbo.vwInterviews", fixed = TRUE)
})

test_that("DBI-BACKEND-13: an NA table name is refused, not passed through", {
  skip_if_no_duckdb()
  # nzchar(NA_character_) is TRUE, so an NA name did not trip the empty-name
  # guard -- it sailed past and reached DBI as a missing value. A YAML key that
  # is present but empty is how that arrives, which makes it a configuration
  # mistake rather than a programming one.
  conn <- creel_connect(
    make_dbi_conn(),
    make_dbi_schema(interviews_table = NA_character_)
  )
  expect_error(fetch_interviews(conn), class = "creel_error_no_table_name")
})

test_that("DBI-BACKEND-14: fractional seconds never render as :60", {
  skip_if_no_duckdb()
  # SQL Server TIME(7) carries fractional seconds. Rounding the seconds
  # remainder on its own turned 59.7 into 60, giving "16:29:60" -- not a time,
  # and .coerce_count_time() would have stored it as readily as a real label.
  # The total is rounded before it is split instead, so 16:29:59.7 becomes the
  # 16:30 it is nearer to.
  f <- tidycreel.connect:::.format_db_time
  expect_equal(f(as.difftime(59399.7, units = "secs")), "16:30")
  expect_equal(f(as.difftime(59459.7, units = "secs")), "16:31")
  expect_equal(f(as.difftime(59400.6, units = "secs")), "16:30:01")
  # Rounding carries at the top of the range too: 23:59:59.7 reaches 86400
  # seconds, which rendered as "24:00". Midnight is the nearest real label.
  expect_equal(f(as.difftime(86399.7, units = "secs")), "00:00")
  expect_equal(f(as.difftime(86399, units = "secs")), "23:59:59")

  # The whole class of failure rather than the cases above. The first sweep
  # stopped at 86399 and tested only for ":60", so it ran past the carry that
  # produced "24:00" without seeing it. Every rendered label must now be a real
  # time of day, field by field.
  #
  # Checked by pattern rather than strptime(): "%H:%M:%OS" returns NA for a
  # label with no seconds, so it would have failed every whole-minute time and
  # told us nothing about the range.
  many <- f(as.difftime(seq(0, 86400, by = 0.7), units = "secs"))
  valid <- grepl("^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$", many)
  expect_true(all(valid))
})

# ---- class ------------------------------------------------------------------

test_that("DBI-BACKEND-08: a DBI connection carries both the new and old class", {
  skip_if_no_duckdb()
  conn <- creel_connect(make_dbi_conn(), make_dbi_schema())
  # Nothing here is SQL Server specific and the suite runs on duckdb, so the
  # methods moved to the generic name. The old one stays in the vector so any
  # method or user code written against it still dispatches.
  expect_s3_class(conn, "creel_connection_dbi")
  expect_s3_class(conn, "creel_connection_sqlserver")
  expect_s3_class(conn, "creel_connection")
  expect_equal(conn$backend, "dbi")
})

test_that("DBI-BACKEND-09: fetches dispatch through the old class name too", {
  skip_if_no_duckdb()
  # Guards the alias: dropping `creel_connection_sqlserver` from the class
  # vector would leave this dispatching to no method.
  conn <- creel_connect(make_dbi_conn(), make_dbi_schema())
  class(conn) <- c("creel_connection_sqlserver", "creel_connection")
  expect_error(fetch_interviews(conn), NA)
})

# ---- discovery is unavailable by design, not unimplemented ------------------

test_that("DBI-BACKEND-10: discovery refuses as inapplicable, not as a stub", {
  skip_if_no_duckdb()
  conn <- creel_connect(make_dbi_conn(), make_dbi_schema())
  # A database connection addresses one set of tables and has no catalogue to
  # enumerate. That is a statement about the backend, so the message must not
  # read as "not yet" -- the previous wording invited someone to implement it.
  expect_error(list_creels(conn), class = "creel_error_discovery_unavailable")
  expect_error(search_creels(conn, "anything"), class = "creel_error_discovery_unavailable")
  expect_error(list_creels(conn), "does not apply")
  expect_false(grepl("not yet", conditionMessage(tryCatch(
    list_creels(conn),
    error = function(e) e
  ))))
})
