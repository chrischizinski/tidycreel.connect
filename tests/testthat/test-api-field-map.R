# Tests for api_field_map argument in creel_connect_api() -- GH #78

# Helpers ----

make_api_conn_custom <- function(api_field_map) {
  schema <- tidycreel::creel_schema(survey_type = "instantaneous")
  creel_connect_api(
    base_url      = "http://test.example.com/api/",
    creel_uids    = "test-uid-001",
    schema        = schema,
    api_field_map = api_field_map
  )
}

# .default_api_field_map() ----

test_that(".default_api_field_map() contains all required endpoints", {
  fm <- tidycreel.connect:::.default_api_field_map()
  expect_true(all(c("interviews", "counts", "catch",
                    "harvest_lengths", "release_lengths") %in% names(fm)))
})

test_that(".default_api_field_map() interviews has AGENCY defaults", {
  fm <- tidycreel.connect:::.default_api_field_map()
  expect_equal(fm$interviews$interview_uid, "api_UID")
  expect_equal(fm$interviews$date,          "api_Date")
  expect_equal(fm$interviews$effort_hours,  "api_TimeFishedHours")
  expect_equal(fm$interviews$effort_minutes,"api_TimeFishedMinutes")
})

test_that(".default_api_field_map() harvest/release use iiUID (no underscore)", {
  fm <- tidycreel.connect:::.default_api_field_map()
  expect_equal(fm$harvest_lengths$interview_uid, "iiUID")
  expect_equal(fm$release_lengths$interview_uid, "iiUID")
})

# .merge_api_field_map() ----

test_that(".merge_api_field_map(NULL) returns defaults unchanged", {
  merged <- tidycreel.connect:::.merge_api_field_map(NULL)
  defaults <- tidycreel.connect:::.default_api_field_map()
  expect_equal(merged, defaults)
})

test_that(".merge_api_field_map() overrides single field", {
  merged <- tidycreel.connect:::.merge_api_field_map(
    list(interviews = list(interview_uid = "my_uid_col"))
  )
  expect_equal(merged$interviews$interview_uid, "my_uid_col")
  expect_equal(merged$interviews$date, "api_Date")
})

test_that(".merge_api_field_map() overrides across multiple endpoints", {
  merged <- tidycreel.connect:::.merge_api_field_map(list(
    interviews = list(interview_uid = "iid"),
    counts     = list(date = "survey_date")
  ))
  expect_equal(merged$interviews$interview_uid, "iid")
  expect_equal(merged$counts$date, "survey_date")
  expect_equal(merged$catch$interview_uid, "api_UID")
})

test_that(".merge_api_field_map() errors on unknown endpoint", {
  expect_error(
    tidycreel.connect:::.merge_api_field_map(list(bad_endpoint = list(x = "y"))),
    "Unknown endpoint"
  )
})

# creel_connect_api() api_field_map integration ----

test_that("creel_connect_api() stores resolved api_field_map in conn$con", {
  conn <- make_api_conn_custom(NULL)
  expect_equal(conn$con$api_field_map$interviews$interview_uid, "api_UID")
})

test_that("creel_connect_api() stores custom api_field_map override", {
  conn <- make_api_conn_custom(list(
    interviews = list(interview_uid = "survey_id", date = "survey_date")
  ))
  expect_equal(conn$con$api_field_map$interviews$interview_uid, "survey_id")
  expect_equal(conn$con$api_field_map$interviews$date,          "survey_date")
  expect_equal(conn$con$api_field_map$interviews$effort_hours,  "api_TimeFishedHours")
})

test_that("creel_connect_api() errors on unknown endpoint in api_field_map", {
  schema <- tidycreel::creel_schema(survey_type = "instantaneous")
  expect_error(
    creel_connect_api(
      base_url      = "http://test.example.com/api/",
      creel_uids    = "uid",
      schema        = schema,
      api_field_map = list(bad_ep = list(x = "y"))
    ),
    "Unknown endpoint"
  )
})

# Schema warning when col-mapping args supplied without api_field_map ----

test_that("creel_connect_api() warns when schema has col-mapping args and api_field_map is NULL", {
  schema_with_mapping <- tidycreel::creel_schema(
    survey_type       = "instantaneous",
    interview_uid_col = "my_interview_id"
  )
  expect_warning(
    creel_connect_api(
      base_url   = "http://test.example.com/api/",
      creel_uids = "uid",
      schema     = schema_with_mapping
    ),
    "schema.*column mappings are ignored|ignored by the API backend",
    perl = TRUE
  )
})

test_that("creel_connect_api() does NOT warn when api_field_map is supplied", {
  schema_with_mapping <- tidycreel::creel_schema(
    survey_type       = "instantaneous",
    interview_uid_col = "my_interview_id"
  )
  expect_no_warning(
    creel_connect_api(
      base_url      = "http://test.example.com/api/",
      creel_uids    = "uid",
      schema        = schema_with_mapping,
      api_field_map = list(interviews = list(interview_uid = "my_interview_id"))
    )
  )
})

test_that("creel_connect_api() does NOT warn when schema has no col-mapping args", {
  schema_bare <- tidycreel::creel_schema(survey_type = "instantaneous")
  expect_no_warning(
    creel_connect_api(
      base_url   = "http://test.example.com/api/",
      creel_uids = "uid",
      schema     = schema_bare
    )
  )
})

# fetch_interviews() with custom field names ----

test_that("fetch_interviews() uses custom api_field_map field names", {
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
  result <- fetch_interviews(conn)
  expect_equal(result$interview_uid, "A1")
  expect_equal(result$catch_count, 2)
  expect_equal(result$trip_status, "complete")
  expect_equal(result$effort, 2 + 30 / 60)
})

test_that("fetch_interviews() computes effort from hours-only when effort_minutes is NULL", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body    = charToRaw(
        '[{"api_UID":"A1","api_Date":"2016-03-28","Num":1,"api_TripKind":"complete","effort_decimal":2.5}]'
      )
    )
  })
  conn <- make_api_conn_custom(list(
    interviews = list(
      effort_hours   = "effort_decimal",
      effort_minutes = NULL
    )
  ))
  result <- fetch_interviews(conn)
  expect_equal(result$effort, 2.5)
})

# fetch_counts() with custom field names ----

test_that("fetch_counts() uses custom api_field_map field names", {
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
  result <- fetch_counts(conn)
  expect_equal(result$bank_anglers, 10)
  expect_equal(result$angler_boats, 5)
})
