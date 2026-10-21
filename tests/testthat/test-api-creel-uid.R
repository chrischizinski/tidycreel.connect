# A multi-creel API connection must say which creel each row came from (#2).
# One request for every UID returned the creels pooled, and no canonical column
# took the creel id, so several waters' interviews, counts and catch reached a
# design as one creel with nothing to split them on.

two_creel_conn <- function(uids = c("creel-a", "creel-b"), pagination = NULL) {
  tidycreel.connect::creel_connect_api(
    base_url      = "http://test.example.com/api/",
    creel_uids    = uids,
    schema        = tidycreel::creel_schema(survey_type = "instantaneous"),
    uid_param     = "survey_id",
    endpoints     = test_api_endpoints(),
    api_field_map = test_api_field_map(),
    pagination    = pagination
  )
}

# The survey_id each mocked request carried.
request_uid <- function(req) httr2::url_parse(req$url)$query[["survey_id"]]

json_response <- function(body) {
  httr2::response(
    200,
    headers = "Content-Type: application/json",
    body    = charToRaw(body)
  )
}

test_that("each creel is requested alone and its rows carry its UID", {
  seen <- character(0)
  httr2::local_mocked_responses(function(req) {
    uid <- request_uid(req)
    seen <<- c(seen, uid)
    # Interview ids repeat across creels, as they do when each creel numbers
    # its own: only the label tells the two "1"s apart.
    ids <- if (uid == "creel-a") c("1", "2") else "1"
    json_response(test_api_interview_json(ids))
  })
  got <- suppressMessages(fetch_interviews(two_creel_conn()))
  # One UID per request: the pooled "creel-a,creel-b" request is what lost
  # the label.
  expect_identical(seen, c("creel-a", "creel-b"))
  expect_identical(got$creel_uid, c("creel-a", "creel-a", "creel-b"))
  expect_identical(got$interview_uid, c("1", "2", "1"))
})

test_that("an endpoint whose payload names no creel is still labelled", {
  # Catch rows carry an interview id and nothing about the creel. A label read
  # from the payload could not exist here; one stamped from the request does.
  httr2::local_mocked_responses(function(req) {
    json_response(sprintf(
      paste0(
        '[{"InterviewID":"1","SpeciesCode":"86","FishCount":%d,',
        '"CatchCategory":"harvested"}]'
      ),
      if (request_uid(req) == "creel-a") 2L else 5L
    ))
  })
  got <- fetch_catch(two_creel_conn())
  expect_identical(got$creel_uid, c("creel-a", "creel-b"))
  expect_equal(got$catch_count, c(2, 5))
  # catch_uid is synthesised after binding, so it stays unique across creels.
  expect_false(anyDuplicated(got$catch_uid) > 0L)
})

test_that("identical rows from two creels are not fetch-created duplicates", {
  # Without the label the two rows below would be exact duplicates of each
  # other; with it they are two creels' interviews, which is what they are.
  httr2::local_mocked_responses(
    function(req) json_response(test_api_interview_json("1"))
  )
  expect_no_warning(
    got <- suppressMessages(fetch_interviews(two_creel_conn())),
    class = "creel_warning_fetch_created_duplicates"
  )
  expect_identical(got$creel_uid, c("creel-a", "creel-b"))
})

test_that("a field one creel omits is NA for that creel, aligned by name", {
  # A survey that never recorded a quantity omits the key. Binding by position
  # would put the other creel's values under the wrong names.
  httr2::local_mocked_responses(function(req) {
    json_response(if (request_uid(req) == "creel-a") {
      paste0(
        '[{"SurveyDate":"2016-03-28","ShoreAnglers":12,',
        '"FishingBoats":2,"OtherBoats":1}]'
      )
    } else {
      '[{"OtherBoats":4,"SurveyDate":"2016-03-29","ShoreAnglers":7}]'
    })
  })
  got <- suppressWarnings(fetch_counts(two_creel_conn()))
  expect_identical(got$creel_uid, c("creel-a", "creel-b"))
  expect_equal(got$bank_anglers, c(12, 7))
  expect_equal(got$angler_boats, c(2, NA))
  expect_equal(got$non_ang_boats, c(1, 4))
})

test_that("an empty creel adds no rows, and all-empty keeps the column", {
  httr2::local_mocked_responses(function(req) {
    a <- request_uid(req) == "creel-a"
    json_response(if (a) test_api_interview_json("1") else "[]")
  })
  got <- suppressMessages(fetch_interviews(two_creel_conn()))
  expect_identical(got$creel_uid, "creel-a")

  # The frame's shape must not depend on whether a creel had data.
  httr2::local_mocked_responses(function(req) json_response("[]"))
  empty <- fetch_interviews(two_creel_conn())
  expect_identical(nrow(empty), 0L)
  expect_true("creel_uid" %in% names(empty))
  expect_type(empty$creel_uid, "character")
})

test_that("paging restarts for each creel", {
  # Each creel is its own paginated query: the second must start at page 1,
  # not continue the first creel's page count.
  calls <- character(0)
  httr2::local_mocked_responses(function(req) {
    q <- httr2::url_parse(req$url)$query
    calls <<- c(calls, paste(q[["survey_id"]], q[["page"]]))
    page <- as.integer(q[["page"]])
    ids <- if (page == 1L) paste0(q[["survey_id"]], "-", 1:2) else character(0)
    json_response(if (length(ids)) test_api_interview_json(ids) else "[]")
  })
  conn <- two_creel_conn(pagination = list(style = "page", page_param = "page"))
  got <- suppressMessages(fetch_interviews(conn))
  expect_identical(calls, c("creel-a 1", "creel-a 2", "creel-b 1", "creel-b 2"))
  expect_identical(got$creel_uid, rep(c("creel-a", "creel-b"), each = 2L))
})

test_that("discovery is not split by creel and gains no label", {
  # Discovery lists the surveys themselves and is sent with no UID filter; it
  # already names each survey's UID in its own field.
  n <- 0L
  httr2::local_mocked_responses(function(req) {
    n <<- n + 1L
    expect_null(request_uid(req))
    json_response(paste0(
      '[{"SurveyID":"creel-a","SurveyTitle":"A","SurveyDescription":"",',
      '"IsActive":true,"IsComplete":true,"Notes":""}]'
    ))
  })
  got <- list_creels(two_creel_conn())
  expect_identical(n, 1L)
  expect_false(".creel_uid" %in% names(got))
})

test_that("two creels counted on one date are not called repeat counts", {
  # The repeat warning says a day was looked at twice. Two creels on one date
  # are two days on two waters; the label is what tells them apart.
  httr2::local_mocked_responses(function(req) {
    json_response(paste0(
      '[{"SurveyDate":"2016-03-28","ShoreAnglers":12,',
      '"FishingBoats":2,"OtherBoats":1}]'
    ))
  })
  expect_no_warning(
    fetch_counts(two_creel_conn()),
    class = "creel_warning_repeated_sampling_units"
  )
  # Within one creel a repeated date still warns.
  httr2::local_mocked_responses(function(req) {
    json_response(paste0(
      '[{"SurveyDate":"2016-03-28","ShoreAnglers":12,',
      '"FishingBoats":2,"OtherBoats":1},',
      '{"SurveyDate":"2016-03-28","ShoreAnglers":9,',
      '"FishingBoats":1,"OtherBoats":0}]'
    ))
  })
  expect_warning(
    fetch_counts(two_creel_conn("creel-a")),
    class = "creel_warning_repeated_sampling_units"
  )
})

test_that("a UID named twice is refused, not fetched twice", {
  # One request per UID means a repeat binds that creel's records again, and
  # catch then gets fresh synthetic ids that make the copies look distinct.
  expect_error(two_creel_conn(c("creel-a", "creel-a")), "more than once")
})

test_that("a source field named like the stamp is refused, not overwritten", {
  # The field map may read it; overwriting would replace its values with the
  # request's UID.
  httr2::local_mocked_responses(function(req) {
    json_response('[{"SurveyDate":"2016-03-28",".creel_uid":"x"}]')
  })
  expect_error(fetch_counts(two_creel_conn()), "reserved")
})
