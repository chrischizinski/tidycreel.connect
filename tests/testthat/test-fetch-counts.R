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

# --- creel_connection_api tests (API-02) ---

test_that("fetch_counts.creel_connection_api() returns canonical columns (API-02)", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body    = charToRaw('[{"api_Date":"2016-03-28","api_NumberAnglers":12}]')
    )
  })
  conn   <- make_api_conn()
  result <- fetch_counts(conn)
  expect_true(is.data.frame(result))
  expect_equal(sort(names(result)), sort(c("date", "angler_count")))
  expect_true(inherits(result$date, "Date"))
  expect_true(is.numeric(result$angler_count))
  expect_equal(result$angler_count, 12)
})

test_that("fetch_counts.creel_connection_api() handles empty API response (API-02)", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(200, headers = "Content-Type: application/json", body = charToRaw("[]"))
  })
  conn   <- make_api_conn()
  result <- fetch_counts(conn)
  expect_equal(nrow(result), 0L)
  expect_true("date" %in% names(result))
  expect_true("angler_count" %in% names(result))
  expect_true(inherits(result$date, "Date"))
})
