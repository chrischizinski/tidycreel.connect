# Profile-driven row cleanup (#27). A long-format source repeats each interview
# once per questionnaire answer, and some sources write a row for a sampled
# date on which nothing was recorded. Both are artifacts of the source, not
# records: left in, each repeat counts an interview's effort and catch again.
# The profile turns the cleanup on; the fetch removes only rows that carry
# nothing or copy another exactly, refuses anything it would have to guess at,
# and says how many rows it removed.

# Interview 1 answered three questions, interview 2 one, and 2024-06-03 was
# sampled with no interview: five source rows, two interviews.
cleanup_interviews <- function() {
  data.frame(
    interview_uid = c(1L, 1L, 1L, 2L, NA),
    date          = c(rep("2024-06-01", 4L), "2024-06-03"),
    catch_count   = c(3L, 3L, 3L, 0L, NA),
    effort_hours  = c(2.5, 2.5, 2.5, 1.0, NA),
    trip_status   = c(rep("complete", 4L), NA),
    question_id   = c(10L, 11L, 12L, 10L, NA),
    answer        = c("yes", "no", "boat", "yes", NA),
    stringsAsFactors = FALSE
  )
}

# A CSV profile over make_test_csv() with `cleanup` lines spliced in.
# `paths` comes from make_test_csv() in the test, whose frame owns the files.
cleanup_profile <- function(paths, cleanup, .env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = .env)
  yaml_path <- file.path(dir, "profile.yml")
  writeLines(c(
    "default:",
    "  backend: csv",
    cleanup,
    "  files:",
    paste0("    ", names(paths), ": ", unlist(paths)),
    "  schema:",
    "    survey_type: instantaneous",
    "    columns:",
    "      effort: effort_hours"
  ), yaml_path)
  yaml_path
}

interview_cleanup <- c(
  "  cleanup:",
  "    interviews:",
  "      drop_placeholders: true",
  "      collapse_repeats: true"
)

# `paths` comes from make_test_csv() in the test, whose frame owns the files.
cleanup_conn <- function(paths, interviews, cleanup = interview_cleanup, .env = parent.frame()) {
  utils::write.csv(interviews, paths$interviews, row.names = FALSE)
  creel_connect_from_yaml(cleanup_profile(paths, cleanup, .env = .env))
}

test_that("cleanup leaves one row per interview, and accounts for every row removed", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  conn <- cleanup_conn(make_test_csv(), cleanup_interviews())
  expect_message(
    result <- fetch_interviews(conn),
    "kept 2 of 5 rows; dropped 1 placeholder row, collapsed 2 exact repeats",
    class = "creel_message_rows_cleaned"
  )
  # Each interview once: a repeat would count its effort and catch again.
  expect_identical(sort(result$interview_uid), c("1", "2"))
  expect_equal(sum(result$effort), 3.5)
  # Nothing leaves unseen: in = dropped + collapsed + kept.
  counts <- attr(result, "cleanup")
  expect_identical(
    counts[["rows_in"]],
    counts[["placeholders_dropped"]] + counts[["repeats_collapsed"]] + counts[["rows_kept"]]
  )
})

test_that("collapsing replaces the duplicate warning, which would describe rows never returned", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  conn <- cleanup_conn(make_test_csv(), cleanup_interviews())
  expect_no_warning(suppressMessages(fetch_interviews(conn)))
})

test_that("without a cleanup block every row comes back, as before", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  # Removing rows has to be asked for.
  conn <- cleanup_conn(make_test_csv(), cleanup_interviews(), cleanup = character(0))
  result <- suppressWarnings(suppressMessages(fetch_interviews(conn)))
  expect_equal(nrow(result), 5L)
  expect_null(attr(result, "cleanup"))
})

test_that("dropping placeholders alone still warns about the repeats left in", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  conn <- cleanup_conn(
    make_test_csv(), cleanup_interviews(),
    cleanup = c("  cleanup:", "    interviews:", "      drop_placeholders: true")
  )
  expect_warning(
    result <- suppressMessages(fetch_interviews(conn)),
    class = "creel_warning_fetch_created_duplicates"
  )
  expect_equal(nrow(result), 4L)
})

test_that("an interview row with data but no interview_uid is refused, not dropped", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  # It cannot be joined to its catch, and it is not empty: the user decides.
  iv <- cleanup_interviews()
  iv$effort_hours[5L] <- 4
  conn <- cleanup_conn(make_test_csv(), iv)
  expect_error(
    suppressMessages(fetch_interviews(conn)),
    "1 row has no interview_uid but carries data",
    class = "creel_error_cleanup_rows_without_uid"
  )
})

test_that("an interview whose rows still differ is refused, naming the column but no value", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  # Picking one effort would be a guess; keeping both counts the trip twice.
  iv <- cleanup_interviews()
  iv$effort_hours[2L] <- 7.25
  conn <- cleanup_conn(make_test_csv(), iv)
  err <- expect_error(
    suppressMessages(fetch_interviews(conn)),
    class = "creel_error_cleanup_conflicting_repeats"
  )
  msg <- conditionMessage(err)
  expect_match(msg, "1 interview still has more than one row")
  expect_match(msg, "effort")
  expect_no_match(msg, "7.25")
})

test_that("a blank count row is dropped, never read as a zero count", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  paths <- make_test_csv()
  counts <- data.frame(
    date          = c("2024-06-01", "2024-06-02", "2024-06-03", "2024-06-04"),
    bank_anglers  = c(12L, 8L, NA, NA),
    angler_boats  = c(0L, 0L, NA, 3L),
    non_ang_boats = c(0L, 0L, NA, NA),
    stringsAsFactors = FALSE
  )
  utils::write.csv(counts, paths$counts, row.names = FALSE)
  conn <- creel_connect_from_yaml(cleanup_profile(
    paths, c("  cleanup:", "    counts:", "      drop_placeholders: true")
  ))
  result <- suppressMessages(fetch_counts(conn))
  # 06-03 recorded nothing and goes; 06-04 recorded boats and stays, its
  # missing shore count still unknown rather than zero.
  expect_identical(as.character(result$date), c("2024-06-01", "2024-06-02", "2024-06-04"))
  expect_true(is.na(result$bank_anglers[3L]))
  expect_identical(attr(result, "cleanup")[["placeholders_dropped"]], 1L)
})

test_that("a corrected copy is compared after the correction", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  # Corrections run first, so a fix applied to every copy of an interview
  # leaves the copies identical and they collapse.
  paths <- make_test_csv()
  iv <- cleanup_interviews()[1:4, ]
  utils::write.csv(iv, paths$interviews, row.names = FALSE)
  yaml_path <- cleanup_profile(paths, c("  corrections: corrections.csv", interview_cleanup))
  writeLines(c(
    "creel_uid,table,date,field,from,to,reason",
    ",interviews,2024-06-01,effort,2.5,3,Clock misread on the sheet"
  ), file.path(dirname(yaml_path), "corrections.csv"))
  conn <- creel_connect_from_yaml(yaml_path)
  result <- suppressMessages(fetch_interviews(conn))
  expect_equal(nrow(result), 2L)
  expect_equal(result$effort[result$interview_uid == "1"], 3)
  expect_false(is.null(attr(result, "corrections")))
})

test_that("the API path collapses within each creel, never across creels", {
  # The same interview_uid in two creels is two interviews.
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
  conn <- creel_connect_api(
    base_url      = "http://test.example.com/api/",
    creel_uids    = c("S1", "S2"),
    schema        = tidycreel::creel_schema(survey_type = "instantaneous"),
    uid_param     = "survey_id",
    endpoints     = test_api_endpoints(),
    api_field_map = test_api_field_map()
  )
  conn$cleanup <- list(interviews = list(collapse_repeats = TRUE))
  result <- suppressMessages(fetch_interviews(conn))
  expect_equal(nrow(result), 2L)
  expect_setequal(result$creel_uid, c("S1", "S2"))
})

test_that("a misspelt or non-logical cleanup step aborts when the profile is read", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  # A typo must not leave the rows in while looking switched on.
  paths <- make_test_csv()
  expect_error(
    creel_connect_from_yaml(cleanup_profile(
      paths, c("  cleanup:", "    interviews:", "      collapse_repeat: true")
    )),
    "Unknown step"
  )
  expect_error(
    creel_connect_from_yaml(cleanup_profile(
      paths, c("  cleanup:", "    counts:", "      collapse_repeats: true")
    )),
    "Unknown step"
  )
  expect_error(
    creel_connect_from_yaml(cleanup_profile(
      paths, c("  cleanup:", "    interviews:", "      collapse_repeats: yes please")
    )),
    "must be true or false"
  )
  expect_error(
    creel_connect_from_yaml(cleanup_profile(
      paths, c("  cleanup:", "    catch:", "      drop_placeholders: true")
    )),
    "Unknown table"
  )
})

cleanup_api_conn <- function(cleanup) {
  conn <- make_api_conn()
  conn$cleanup <- cleanup
  conn
}

mock_interviews_json <- function(json) {
  httr2::local_mocked_responses(function(req) {
    httr2::response(200, headers = "Content-Type: application/json", body = charToRaw(json))
  }, env = parent.frame())
}

test_that("a blank-string interview_uid is missing, not an id", {
  # An API may write a missing id as "" rather than null. Read as an id, the
  # empty row would be kept and an orphan row with data waved through.
  mock_interviews_json(paste0(
    '[{"InterviewID":"A1","SurveyDate":"2016-03-28","TripStatus":"complete",',
    '"HoursFished":2,"MinutesFished":30},',
    '{"InterviewID":"","SurveyDate":"2016-03-29","TripStatus":"",',
    '"HoursFished":null,"MinutesFished":null}]'
  ))
  conn <- cleanup_api_conn(list(interviews = list(drop_placeholders = TRUE)))
  result <- suppressMessages(fetch_interviews(conn))
  expect_identical(result$interview_uid, "A1")

  mock_interviews_json(paste0(
    '[{"InterviewID":"","SurveyDate":"2016-03-29","TripStatus":"complete",',
    '"HoursFished":2,"MinutesFished":0}]'
  ))
  conn <- cleanup_api_conn(list(interviews = list(drop_placeholders = TRUE)))
  expect_error(
    suppressMessages(fetch_interviews(conn)),
    class = "creel_error_cleanup_rows_without_uid"
  )
})

test_that("an empty API fetch carries the cleanup accounting too", {
  # A script that reads attr(x, "cleanup") must not fail only on a quiet day.
  mock_interviews_json("[]")
  conn <- cleanup_api_conn(list(
    interviews = list(collapse_repeats = TRUE),
    counts = list(drop_placeholders = TRUE)
  ))
  iv <- suppressMessages(fetch_interviews(conn))
  expect_identical(attr(iv, "cleanup")[["rows_kept"]], 0L)
  ct <- suppressMessages(fetch_counts(conn))
  expect_identical(attr(ct, "cleanup")[["rows_in"]], 0L)
})
