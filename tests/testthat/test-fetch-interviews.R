# Tests for fetch_interviews() — FETCH-01, FETCH-06, BACKEND-01

test_that("fetch_interviews() returns tibble with canonical columns (FETCH-01)", {
  paths <- make_test_csv()
  schema <- make_test_schema()
  conn <- creel_connect(paths, schema)
  result <- fetch_interviews(conn)
  expect_true(is.data.frame(result))
  expect_true("date" %in% names(result))
  expect_true("catch_count" %in% names(result))
  expect_true("effort" %in% names(result))
  expect_true("trip_status" %in% names(result))
  # effort must be renamed from effort_hours -> effort
  expect_false("effort_hours" %in% names(result))
  # date must be Date class
  expect_true(inherits(result$date, "Date"))
  # numeric columns
  expect_true(is.numeric(result$catch_count))
  expect_true(is.numeric(result$effort))
  # character
  expect_true(is.character(result$trip_status))
})

test_that("fetch_interviews() handles BOM CSV without corrupted column names (BACKEND-01)", {
  paths <- make_test_csv_bom()
  schema <- make_test_schema()
  conn <- creel_connect(paths, schema)
  result <- fetch_interviews(conn)
  expect_true(is.data.frame(result))
  # No BOM bytes in column names
  for (nm in names(result)) {
    expect_false(grepl("\xef\xbb\xbf", nm, useBytes = TRUE))
  }
  expect_true("date" %in% names(result))
})

test_that("fetch_interviews() aborts with clear error when required column is missing (FETCH-06)", {
  df_bad <- data.frame(date = Sys.Date(), catch_count = 1.0, stringsAsFactors = FALSE)
  expect_error(
    tidycreel.connect:::validate_fetch_interviews(df_bad),
    "interview_uid"
  )
  expect_error(
    tidycreel.connect:::validate_fetch_interviews(df_bad),
    "effort"
  )
})

test_that("fetch_interviews() aborts with clear error when column has wrong type (FETCH-06)", {
  df_bad <- data.frame(
    interview_uid = "A",
    date = "2024-06-01", # character, not Date
    catch_count = 1.0,
    effort = 2.5,
    trip_status = "complete",
    stringsAsFactors = FALSE
  )
  expect_error(
    tidycreel.connect:::validate_fetch_interviews(df_bad),
    "date"
  )
})
