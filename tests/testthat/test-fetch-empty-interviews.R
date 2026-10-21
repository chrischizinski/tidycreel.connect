# An empty API interviews response must have the shape of a non-empty one
# (#19). The empty frame carried only the five core columns, while a response
# with rows also carries every optional field the field map names, so a script
# that binds fetches, or selects n_anglers, failed only on a quiet day.

# Every optional interview field mapped, plus a stratum.
full_field_map <- function() {
  list(
    interview_uid  = "InterviewID",
    date           = "SurveyDate",
    trip_status    = "TripStatus",
    effort_hours   = "HoursFished",
    catch_count    = "FishKept",
    n_anglers      = "PartySize",
    angler_type    = "AnglerType",
    site           = "SiteName",
    circuit        = "Circuit",
    n_counted      = "Counted",
    n_interviewed  = "Asked",
    angler_method  = "Method",
    species_sought = "Target",
    refused        = "Refused",
    zip_code       = "Zip",
    day_type       = "DayType"
  )
}

full_conn <- function(field_map = full_field_map()) {
  make_api_conn(
    field_map = list(interviews = field_map),
    endpoints = list(interviews = "v2/interviews"),
    schema    = tidycreel::creel_schema(
      survey_type = "instantaneous",
      strata_cols = c(day_type = "day_type")
    )
  )
}

mock_body <- function(body) {
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body    = charToRaw(body)
    )
  }, env = parent.frame())
}

test_that("an empty response has the same columns and types as a full one", {
  mock_body(paste0(
    '[{"InterviewID":"A1","SurveyDate":"2016-03-28","TripStatus":"complete",',
    '"HoursFished":2,"FishKept":1,"PartySize":2,"AnglerType":"bank",',
    '"SiteName":"North","Circuit":"C1","Counted":4,"Asked":2,',
    '"Method":"bait","Target":"walleye","Refused":false,"Zip":"68503",',
    '"DayType":"weekday"}]'
  ))
  full <- suppressMessages(fetch_interviews(full_conn()))

  mock_body("[]")
  empty <- fetch_interviews(full_conn())

  expect_identical(nrow(empty), 0L)
  # Compared against the fetch with rows rather than a list written here, so
  # a type changed on one path and not the other fails this test. Strata
  # excepted: see the next test.
  expect_identical(sort(names(empty)), sort(setdiff(names(full), "day_type")))
  classes <- function(df) lapply(df[sort(names(empty))], class)
  expect_identical(classes(empty), classes(full))
})

test_that("an empty response omits the optional fields the map does not name", {
  # Only what a full fetch would carry: an unnamed field is absent there too.
  fm <- full_field_map()
  unnamed <- c("n_anglers", "zip_code", "catch_count")
  fm[unnamed] <- NULL
  mock_body("[]")
  empty <- fetch_interviews(full_conn(fm))
  expect_false(any(unnamed %in% names(empty)))
  expect_true(all(c("site", "refused") %in% names(empty)))
})

test_that("strata stay out of an empty response rather than guess a type", {
  # A stratum keeps the source's type: a numeric code here. A zero-length
  # column of any one type would refuse to bind with some source's populated
  # fetch, so the column is left out, as before #19.
  mock_body(paste0(
    '[{"InterviewID":"A1","SurveyDate":"2016-03-28","TripStatus":"complete",',
    '"HoursFished":2,"DayType":1}]'
  ))
  full <- suppressMessages(fetch_interviews(full_conn()))
  expect_type(full$day_type, "integer")
  mock_body("[]")
  expect_false("day_type" %in% names(fetch_interviews(full_conn())))
})
