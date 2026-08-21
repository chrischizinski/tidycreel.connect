# Tests for the api_field_map / endpoints contract in creel_connect_api()
# (GH #78, and the agency-agnostic rewrite)
#
# The package ships no endpoint paths and no field names, so every connection
# here describes its own API. All names below are invented.

# Helpers ----

# Merge a partial field map over the test profile, so a test can vary one
# endpoint without restating the rest.
make_api_conn_custom <- function(field_map) {
  profile <- test_api_field_map() # nolint: object_usage_linter
  for (ep in names(field_map)) profile[[ep]] <- field_map[[ep]]
  make_api_conn(field_map = profile) # nolint: object_usage_linter
}

# The contract is required, not defaulted ----

test_that("creel_connect_api() aborts when api_field_map is not supplied", {
  # A default field map would be one organisation's contract shipped as
  # everyone's: it would decode their payload and silently misread every other.
  expect_error(
    creel_connect_api(
      base_url   = "http://test.example.com/api/",
      creel_uids = "uid",
      schema     = tidycreel::creel_schema(survey_type = "instantaneous"),
      uid_param  = "survey_id",
      endpoints  = test_api_endpoints()
    ),
    "api_field_map.*required",
    perl = TRUE
  )
})

test_that("creel_connect_api() aborts when endpoints are not supplied", {
  expect_error(
    creel_connect_api(
      base_url      = "http://test.example.com/api/",
      creel_uids    = "uid",
      schema        = tidycreel::creel_schema(survey_type = "instantaneous"),
      uid_param     = "survey_id",
      api_field_map = test_api_field_map()
    ),
    "endpoints.*required",
    perl = TRUE
  )
})

test_that("creel_connect_api() aborts when uid_param is not supplied", {
  # The query parameter name is as deployment-specific as the paths are.
  expect_error(
    creel_connect_api(
      base_url      = "http://test.example.com/api/",
      creel_uids    = "uid",
      schema        = tidycreel::creel_schema(survey_type = "instantaneous"),
      endpoints     = test_api_endpoints(),
      api_field_map = test_api_field_map()
    ),
    "uid_param.*required",
    perl = TRUE
  )
})

test_that("the abort points at the template profile", {
  # The error has to leave the user somewhere to go, or requiring the contract
  # just makes the backend look broken.
  expect_error(
    creel_connect_api(
      base_url   = "http://test.example.com/api/",
      creel_uids = "uid",
      schema     = tidycreel::creel_schema(survey_type = "instantaneous"),
      uid_param  = "survey_id",
      endpoints  = test_api_endpoints()
    ),
    "api-profile-example"
  )
})

test_that("the template profile is installed and parses", {
  path <- system.file("extdata", "api-profile-example.yml", package = "tidycreel.connect")
  expect_true(nzchar(path))
  skip_if_not_installed("yaml")
  cfg <- yaml::read_yaml(path)$default
  expect_equal(cfg$backend, "api")
  expect_true(all(c("interviews", "counts") %in% names(cfg$endpoints)))
  expect_equal(cfg$field_map$interviews$n_anglers, "PartySize")
})

# Validation ----

test_that("creel_connect_api() errors on unknown endpoint in api_field_map", {
  expect_error(
    make_api_conn(field_map = list(bad_ep = list(x = "y"))),
    "Unknown endpoint"
  )
})

test_that("creel_connect_api() errors on unknown endpoint name in endpoints", {
  expect_error(
    make_api_conn(endpoints = list(bad_ep = "v2/nope")),
    "Unknown endpoint name"
  )
})

test_that("creel_connect_api() rejects a non-string raw field name", {
  # A field name arriving as a number or a vector would silently match nothing
  # and the columns would go missing several stages later.
  expect_error(
    make_api_conn(field_map = list(interviews = list(date = 42))),
    "non-empty single string"
  )
})

test_that("creel_connect_api() stores the field map on the connection", {
  conn <- make_api_conn()
  expect_equal(conn$con$api_field_map$interviews$interview_uid, "InterviewID")
  expect_equal(conn$con$endpoints$interviews, "v2/interviews")
  expect_equal(conn$con$uid_param, "survey_id")
})

# Fetching an endpoint the profile does not describe ----

test_that("fetch_*() aborts when the endpoint has no configured path", {
  conn <- make_api_conn(endpoints = list(counts = "v2/counts"))
  expect_error(fetch_interviews(conn), "No .*interviews.* endpoint is configured")
})

test_that("fetch_*() aborts when the endpoint has no configured field names", {
  # Refused rather than fetched-and-dropped: with no names every column would be
  # discarded by the rename and the failure would surface as "column missing".
  conn <- make_api_conn(field_map = list(counts = test_api_field_map()$counts))
  expect_error(fetch_interviews(conn), "No field names are configured")
})

# Schema warning: schema column mappings are not API field names ----

test_that("creel_connect_api() warns when the schema carries column mappings", {
  schema_with_mapping <- tidycreel::creel_schema(
    survey_type       = "instantaneous",
    interview_uid_col = "my_interview_id"
  )
  expect_warning(
    make_api_conn(schema = schema_with_mapping),
    "ignored by the API backend"
  )
})

test_that("creel_connect_api() does NOT warn when the schema has no column mappings", {
  expect_no_warning(make_api_conn())
})

# fetch_*() with the caller's field names ----

test_that("fetch_interviews() uses the configured field names", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body    = charToRaw(
        '[{"my_uid":"A1","my_date":"2016-03-28","my_catch":2,
           "my_status":"complete","my_hrs":2,"my_min":30}]'
      )
    )
  })
  conn <- make_api_conn_custom(list(
    interviews = list(
      interview_uid  = "my_uid",
      date           = "my_date",
      catch_count    = "my_catch",
      trip_status    = "my_status",
      effort_hours   = "my_hrs",
      effort_minutes = "my_min"
    )
  ))
  result <- suppressMessages(fetch_interviews(conn))
  expect_equal(result$interview_uid, "A1")
  expect_equal(result$catch_count, 2)
  expect_equal(result$trip_status, "complete")
  expect_equal(result$effort, 2 + 30 / 60)
})

test_that("fetch_interviews() computes effort from hours alone when no minutes field is named", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body    = charToRaw(paste0(
        '[{"InterviewID":"A1","SurveyDate":"2016-03-28","TripStatus":"complete",',
        '"effort_decimal":2.5}]'
      ))
    )
  })
  conn <- make_api_conn_custom(list(
    interviews = list(
      interview_uid = "InterviewID",
      date          = "SurveyDate",
      trip_status   = "TripStatus",
      effort_hours  = "effort_decimal"
    )
  ))
  result <- suppressMessages(fetch_interviews(conn))
  expect_equal(result$effort, 2.5)
})

test_that("fetch_counts() uses the configured field names", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body    = charToRaw('[{"survey_dt":"2016-03-28","shore":10,"boats":5,"empty":2}]')
    )
  })
  conn <- make_api_conn_custom(list(
    counts = list(
      date          = "survey_dt",
      bank_anglers  = "shore",
      angler_boats  = "boats",
      non_ang_boats = "empty"
    )
  ))
  result <- suppressMessages(fetch_counts(conn))
  expect_equal(result$bank_anglers, 10)
  expect_equal(result$angler_boats, 5)
})
