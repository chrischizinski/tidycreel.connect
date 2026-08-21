# Tests for list_creels() and search_creels() — API-07, API-08

# --- Shared fixture body ---
# Field names come from the test profile in helper-api.R; all of them invented
# (SurveyID, SurveyTitle, SurveyDescription, IsActive, IsComplete, Notes)
discovery_body_two_surveys <- charToRaw(paste0(
  '[',
  '{"SurveyID":"S001","SurveyTitle":"Calamus 2016","SurveyDescription":"Summer survey",',
  '"IsActive":true,"IsComplete":false,"Notes":"Pilot"},',
  '{"SurveyID":"S002","SurveyTitle":"Cedar 2018","SurveyDescription":"Fish survey",',
  '"IsActive":true,"IsComplete":true,"Notes":""}',
  ']'
))

mock_ok <- function(body) {
  httr2::response(200, headers = "Content-Type: application/json", body = body)
}

# --- list_creels() tests (API-07) ---

test_that("list_creels.creel_connection_api() returns data.frame with six canonical columns (API-07)", {
  httr2::local_mocked_responses(function(req) mock_ok(discovery_body_two_surveys))
  conn   <- make_api_conn()
  result <- list_creels(conn)
  expect_true(is.data.frame(result))
  expect_equal(
    sort(names(result)),
    sort(c("creel_uid", "title", "description", "active", "data_complete", "comments"))
  )
  expect_equal(nrow(result), 2L)
})

test_that("list_creels.creel_connection_api() coerces types correctly (API-07)", {
  httr2::local_mocked_responses(function(req) mock_ok(discovery_body_two_surveys))
  conn   <- make_api_conn()
  result <- list_creels(conn)
  expect_true(is.character(result$creel_uid))
  expect_true(is.logical(result$active))
  expect_true(is.logical(result$data_complete))
})

test_that("list_creels.creel_connection_api() returns 0-row tibble on empty API response (API-10)", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(200, headers = "Content-Type: application/json", body = charToRaw("[]"))
  })
  conn   <- make_api_conn()
  result <- list_creels(conn)
  expect_equal(nrow(result), 0L)
  expect_equal(
    sort(names(result)),
    sort(c("creel_uid", "title", "description", "active", "data_complete", "comments"))
  )
  # API-10: empty response must be a tibble, not a plain data.frame
  expect_true(inherits(result, "tbl_df"))
  # Column types must be preserved even with 0 rows
  expect_true(is.character(result$creel_uid))
  expect_true(is.character(result$title))
  expect_true(is.character(result$description))
  expect_true(is.logical(result$active))
  expect_true(is.logical(result$data_complete))
  expect_true(is.character(result$comments))
})

test_that("list_creels.creel_connection_csv() aborts with not-supported error (API-07)", {
  conn_csv <- structure(list(), class = c("creel_connection_csv", "creel_connection"))
  expect_error(list_creels(conn_csv), "not supported")
  expect_error(list_creels(conn_csv), "creel_connection_csv")
})

test_that("list_creels.creel_connection_sqlserver() aborts with not-supported error (API-07)", {
  conn_sql <- structure(list(), class = c("creel_connection_sqlserver", "creel_connection"))
  expect_error(list_creels(conn_sql), "not supported")
  expect_error(list_creels(conn_sql), "creel_connection_sqlserver")
})

# --- search_creels() tests (API-08) ---

test_that("search_creels.creel_connection_api() returns matching rows by title (API-08)", {
  httr2::local_mocked_responses(function(req) mock_ok(discovery_body_two_surveys))
  conn   <- make_api_conn()
  result <- search_creels(conn, "Calamus")
  expect_equal(nrow(result), 1L)
  expect_equal(result$creel_uid, "S001")
})

test_that("search_creels.creel_connection_api() is case-insensitive (API-08)", {
  httr2::local_mocked_responses(function(req) mock_ok(discovery_body_two_surveys))
  conn    <- make_api_conn()
  result  <- search_creels(conn, "calamus")
  expect_equal(nrow(result), 1L)
  expect_equal(result$creel_uid, "S001")
})

test_that("search_creels.creel_connection_api() matches on description column (API-08)", {
  httr2::local_mocked_responses(function(req) mock_ok(discovery_body_two_surveys))
  conn   <- make_api_conn()
  result <- search_creels(conn, "summer")  # "Summer survey" is in api_Title -> description
  expect_equal(nrow(result), 1L)
  expect_equal(result$creel_uid, "S001")
})

test_that("search_creels.creel_connection_api() returns 0-row data.frame on no match (API-08)", {
  httr2::local_mocked_responses(function(req) mock_ok(discovery_body_two_surveys))
  conn   <- make_api_conn()
  result <- search_creels(conn, "zzz_nomatch_zzz")
  expect_equal(nrow(result), 0L)
  expect_equal(
    sort(names(result)),
    sort(c("creel_uid", "title", "description", "active", "data_complete", "comments"))
  )
})

test_that("search_creels.creel_connection_api() aborts on empty keyword (API-08)", {
  conn <- make_api_conn()
  expect_error(search_creels(conn, ""), "keyword")
})

test_that("search_creels.creel_connection_csv() aborts with not-supported error (API-08)", {
  conn_csv <- structure(list(), class = c("creel_connection_csv", "creel_connection"))
  expect_error(search_creels(conn_csv, "test"), "not supported")
})

test_that("search_creels.creel_connection_sqlserver() aborts with not-supported error (API-08)", {
  conn_sql <- structure(list(), class = c("creel_connection_sqlserver", "creel_connection"))
  expect_error(search_creels(conn_sql, "test"), "not supported")
})
