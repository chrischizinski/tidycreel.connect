# Tests for fetch_counts() — FETCH-02, FETCH-06

test_that("fetch_counts() returns tibble with canonical columns (FETCH-02)", {
  paths <- make_test_csv()
  schema <- make_test_schema()
  conn <- creel_connect(paths, schema)
  result <- fetch_counts(conn)
  expect_true(is.data.frame(result))
  expect_true("date" %in% names(result))
  expect_true("angler_count" %in% names(result))
  expect_true(inherits(result$date, "Date"))
  expect_true(is.numeric(result$angler_count))
})

test_that("fetch_counts() aborts with clear error when required column is missing (FETCH-06)", {
  df_bad <- data.frame(date = Sys.Date(), stringsAsFactors = FALSE)
  expect_error(
    tidycreel.connect:::validate_fetch_counts(df_bad),
    "angler_count"
  )
})
