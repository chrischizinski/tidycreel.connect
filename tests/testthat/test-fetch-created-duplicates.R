# Rows the fetch itself made identical (#1). A long-format source -- one row
# per interview x questionnaire answer -- keeps the answer in columns nothing
# maps. Dropping them leaves exact duplicates, and tidycreel keeps a repeated
# interview_uid on purpose (bus-route designs need it), so each copy counts that
# interview's effort and catch again. Nothing downstream catches it.

# Interview 1 answered three questions, interview 2 one: four source rows, two
# interviews.
long_format_interviews <- function() {
  data.frame(
    interview_uid = c(1L, 1L, 1L, 2L),
    date          = "2024-06-01",
    catch_count   = c(3L, 3L, 3L, 0L),
    effort_hours  = c(2.5, 2.5, 2.5, 1.0),
    trip_status   = "complete",
    question_id   = c(10L, 11L, 12L, 10L),
    answer        = c("yes", "no", "boat", "yes"),
    stringsAsFactors = FALSE
  )
}

csv_conn_with <- function(paths, interviews) {
  utils::write.csv(interviews, paths$interviews, row.names = FALSE)
  creel_connect(paths, make_test_schema())
}

test_that("a long-format source warns with the count it created and the columns that split it", {
  skip_if_not_installed("withr")
  conn <- csv_conn_with(make_test_csv(), long_format_interviews())
  w <- NULL
  result <- withCallingHandlers(
    suppressMessages(fetch_interviews(conn)),
    creel_warning_fetch_created_duplicates = function(cnd) {
      w <<- cnd
      invokeRestart("muffleWarning")
    }
  )
  expect_s3_class(w, "creel_warning")
  msg <- conditionMessage(w)
  # 4 distinct source rows, 2 distinct fetched: the fetch created 2.
  expect_match(msg, "made 2 rows exact duplicates")
  expect_match(msg, "4 rows, 2 distinct")
  expect_match(msg, "question_id")
  expect_match(msg, "answer")
  # The rows are still returned as they are: the caller decides how to collapse.
  expect_equal(nrow(result), 4L)
})

test_that("rows already identical in the source are not blamed on the fetch", {
  skip_if_not_installed("withr")
  # Same duplicate count after the fetch, but the source had it too: the fetch
  # dropped nothing that told them apart.
  iv <- long_format_interviews()
  iv$question_id <- NULL
  iv$answer <- NULL
  conn <- csv_conn_with(make_test_csv(), iv)
  expect_no_warning(suppressMessages(fetch_interviews(conn)))
})

test_that("a dropped column that tells no rows apart does not warn", {
  skip_if_not_installed("withr")
  # One row per interview: dropping a column cannot create a duplicate.
  iv <- long_format_interviews()[c(1L, 4L), ]
  conn <- csv_conn_with(make_test_csv(), iv)
  expect_no_warning(suppressMessages(fetch_interviews(conn)))
})

test_that("the API path warns the same way", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body    = charToRaw(paste0(
        '[{"InterviewID":"A1","SurveyDate":"2016-03-28","TripStatus":"complete",',
        '"HoursFished":2,"MinutesFished":30,"QuestionID":1},',
        '{"InterviewID":"A1","SurveyDate":"2016-03-28","TripStatus":"complete",',
        '"HoursFished":2,"MinutesFished":30,"QuestionID":2}]'
      ))
    )
  })
  conn <- make_api_conn()
  expect_warning(
    suppressMessages(fetch_interviews(conn)),
    "QuestionID",
    class = "creel_warning_fetch_created_duplicates"
  )
})

test_that("a carried column whose values a map joins is not called dropped", {
  skip_if_not_installed("withr")
  # TripKind is mapped to trip_status, and "1" -> "complete" makes the two rows
  # identical. Saying TripKind "is not carried through" would send the caller
  # to map a column that is already mapped.
  iv <- long_format_interviews()[c(1L, 2L), ]
  iv$question_id <- NULL
  iv$answer <- NULL
  names(iv)[names(iv) == "trip_status"] <- "TripKind"
  iv$TripKind <- c("1", "complete")
  paths <- make_test_csv()
  utils::write.csv(iv, paths$interviews, row.names = FALSE)
  schema <- tidycreel::creel_schema(
    survey_type       = "instantaneous",
    interview_uid_col = "interview_uid",
    date_col          = "date",
    catch_col         = "catch_count",
    effort_col        = "effort_hours",
    trip_status_col   = "TripKind",
    value_maps        = list(trip_status = c("1" = "complete"))
  )
  conn <- creel_connect(paths, schema)
  w <- NULL
  withCallingHandlers(
    suppressMessages(fetch_interviews(conn)),
    creel_warning_fetch_created_duplicates = function(cnd) {
      w <<- cnd
      invokeRestart("muffleWarning")
    }
  )
  msg <- conditionMessage(w)
  expect_match(msg, "TripKind")
  expect_match(msg, "mapped to the same value")
  expect_no_match(msg, "not carried through")
})

test_that("a dropped nested JSON column that alone tells rows apart is seen", {
  # Nested values parse to a data.frame or list column, which duplicated()
  # cannot compare directly; skipping them missed exactly this case.
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body    = charToRaw(paste0(
        '[{"InterviewID":"A1","SurveyDate":"2016-03-28","TripStatus":"complete",',
        '"HoursFished":2,"MinutesFished":30,"Answer":{"q":1,"a":"yes"}},',
        '{"InterviewID":"A1","SurveyDate":"2016-03-28","TripStatus":"complete",',
        '"HoursFished":2,"MinutesFished":30,"Answer":{"q":2,"a":"no"}}]'
      ))
    )
  })
  expect_warning(
    suppressMessages(fetch_interviews(make_api_conn())),
    "Answer",
    class = "creel_warning_fetch_created_duplicates"
  )
})
