# Tests for .api_fetch() hardening — API-06

test_that(".api_fetch() returns data.frame on 200 response (API-06)", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body    = charToRaw('[{"api_UID":"A1","api_Date":"2016-03-28","Num":2,"api_TripKind":"complete","api_TimeFishedHours":2,"api_TimeFishedMinutes":30}]')
    )
  })
  conn   <- make_api_conn()
  result <- fetch_interviews(conn)
  expect_true(is.data.frame(result))
})

test_that(".api_fetch() aborts with cli message on 404 (API-06)", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      404,
      headers = "Content-Type: application/json",
      body    = charToRaw('{"error":"Not Found"}')
    )
  })
  conn <- make_api_conn()
  expect_error(fetch_interviews(conn), "API request failed \\[404\\]")
})

test_that(".api_fetch() returns empty data.frame for empty JSON array response (API-06)", {
  # Validates the null/empty-array guard path in .api_fetch(); req_retry is wired
  # but local_mocked_responses intercepts before the retry loop in httr2 1.2.2.
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body    = charToRaw("[]")
    )
  })
  conn   <- make_api_conn()
  result <- fetch_interviews(conn)
  expect_equal(nrow(result), 0L)
})

test_that(".api_fetch() aborts after exhausting 3 retries on 429 (API-06)", {
  httr2::local_mocked_responses(list(
    httr2::response(429, headers = "Content-Type: application/json", body = charToRaw("")),
    httr2::response(429, headers = "Content-Type: application/json", body = charToRaw("")),
    httr2::response(429, headers = "Content-Type: application/json", body = charToRaw(""))
  ))
  conn <- make_api_conn()
  expect_error(fetch_interviews(conn), "API request failed")
})
