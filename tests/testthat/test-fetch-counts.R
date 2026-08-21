# Tests for fetch_counts() — FETCH-02, FETCH-06, API-02, API-11

EXPECTED_COLS <- c("date", "bank_anglers", "angler_boats", "non_ang_boats")

test_that("fetch_counts() returns data frame with canonical columns (FETCH-02)", {
  paths  <- make_test_csv()
  schema <- make_test_schema()
  conn   <- creel_connect(paths, schema)
  result <- fetch_counts(conn)
  expect_true(is.data.frame(result))
  expect_equal(sort(names(result)), sort(EXPECTED_COLS))
  expect_true(inherits(result$date, "Date"))
  expect_true(is.numeric(result$bank_anglers))
  expect_true(is.numeric(result$angler_boats))
})

test_that("fetch_counts() aborts with clear error when required column is missing (FETCH-06)", {
  df_bad <- data.frame(date = Sys.Date(), stringsAsFactors = FALSE)
  expect_error(
    tidycreel.connect:::validate_fetch_counts(df_bad),
    "bank_anglers"
  )
})

# --- creel_connection_api tests (API-02, API-11) ---

test_that("fetch_counts.creel_connection_api() returns canonical columns (API-02)", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body    = charToRaw('[{"SurveyDate":"2016-03-28","ShoreAnglers":12,"FishingBoats":2,"OtherBoats":1}]')
    )
  })
  conn   <- make_api_conn()
  result <- fetch_counts(conn)
  expect_true(is.data.frame(result))
  expect_equal(sort(names(result)), sort(EXPECTED_COLS))
  expect_true(inherits(result$date, "Date"))
  expect_true(is.numeric(result$bank_anglers))
  expect_equal(result$bank_anglers, 12)
  expect_equal(result$angler_boats, 2)
  expect_equal(result$non_ang_boats, 1)
})

test_that("fetch_counts.creel_connection_api() handles empty API response (API-02)", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(200, headers = "Content-Type: application/json", body = charToRaw("[]"))
  })
  conn   <- make_api_conn()
  result <- fetch_counts(conn)
  expect_equal(nrow(result), 0L)
  expect_equal(sort(names(result)), sort(EXPECTED_COLS))
  expect_true(inherits(result$date, "Date"))
})

test_that("fetch_counts.creel_connection_api() silently drops absent optional fields (API-11)", {
  # A source that counts no boats: only date and bank_anglers come back
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body    = charToRaw('[{"SurveyDate":"2016-03-28","ShoreAnglers":8}]')
    )
  })
  conn   <- make_api_conn()
  result <- fetch_counts(conn)
  expect_true("bank_anglers" %in% names(result))
  expect_equal(result$bank_anglers, 8)
  # angler_boats and non_ang_boats absent from API response — silently dropped
  expect_false("angler_boats" %in% names(result))
})
