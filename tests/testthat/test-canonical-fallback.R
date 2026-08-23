# GH #168: a source that already uses tidycreel's names needed a schema entry
# per column anyway -- `date_col = "date"` to load a column called `date`. The
# rename now falls back to the canonical name when nothing is mapped, the way
# .strata_direct_map() already did on the API path.
#
# What must NOT happen is an explicit mapping being second-guessed: a name that
# does not match the source is a configuration error, and rescuing it with a
# differently-named column would hide it.

canonical_csv <- function(interviews) {
  dir <- withr::local_tempdir(.local_envir = parent.frame())
  paths <- list(
    interviews      = file.path(dir, "interviews.csv"),
    counts          = file.path(dir, "counts.csv"),
    catch           = file.path(dir, "catch.csv"),
    harvest_lengths = file.path(dir, "harvest_lengths.csv"),
    release_lengths = file.path(dir, "release_lengths.csv")
  )
  utils::write.csv(interviews, paths$interviews, row.names = FALSE)
  empty <- data.frame(x = integer(0))
  for (nm in c("counts", "catch", "harvest_lengths", "release_lengths")) {
    utils::write.csv(empty, paths[[nm]], row.names = FALSE)
  }
  paths
}

canonical_interviews <- function() {
  data.frame(
    interview_uid = 1L:2L,
    date          = as.Date(c("2024-06-01", "2024-06-02")),
    catch_count   = c(3L, 0L),
    effort        = c(2.5, 1.0),
    trip_status   = c("complete", "incomplete"),
    stringsAsFactors = FALSE
  )
}

test_that("an already-canonical source fetches with survey_type alone", {
  skip_if_not_installed("withr")
  paths <- canonical_csv(canonical_interviews())
  conn <- creel_connect(paths, tidycreel::creel_schema(survey_type = "instantaneous"))
  interviews <- suppressMessages(fetch_interviews(conn))
  # The values, not just the names: a fallback that matched the name but took
  # the wrong column would leave the frame the right shape and wrong.
  expect_equal(nrow(interviews), 2L)
  expect_equal(interviews$catch_count, c(3, 0))
  expect_equal(interviews$effort, c(2.5, 1.0))
  expect_equal(as.character(interviews$date), c("2024-06-01", "2024-06-02"))
})

test_that("columns taken by canonical name are named, not taken silently", {
  skip_if_not_installed("withr")
  paths <- canonical_csv(canonical_interviews())
  conn <- creel_connect(paths, tidycreel::creel_schema(survey_type = "instantaneous"))
  msg <- paste(
    capture.output(fetch_interviews(conn), type = "message"),
    collapse = " "
  )
  expect_match(msg, "taking 5 columns by canonical name")
  expect_match(msg, "interview_uid")
  expect_match(msg, "trip_status")
})

test_that("a single adopted column does not trip cli pluralization", {
  skip_if_not_installed("withr")
  # cli aborts with "Cannot pluralize without a quantity" when a string carries
  # two quantities, and the singular branch is where that shows up first.
  iv <- canonical_interviews()
  names(iv)[names(iv) == "interview_uid"] <- "InterviewID"
  names(iv)[names(iv) == "catch_count"] <- "TotalCatch"
  names(iv)[names(iv) == "effort"] <- "HoursFished"
  names(iv)[names(iv) == "trip_status"] <- "TripStatus"
  paths <- canonical_csv(iv)
  conn <- creel_connect(paths, tidycreel::creel_schema(
    survey_type       = "instantaneous",
    interview_uid_col = "InterviewID",
    catch_col         = "TotalCatch",
    effort_col        = "HoursFished",
    trip_status_col   = "TripStatus"
  ))
  msg <- paste(capture.output(fetch_interviews(conn), type = "message"), collapse = " ")
  expect_match(msg, "taking 1 column by canonical name")
  expect_no_match(msg, "1 columns")
})

test_that("a fully mapped source says nothing about canonical names", {
  skip_if_not_installed("withr")
  iv <- canonical_interviews()
  names(iv) <- c("InterviewID", "SurveyDate", "TotalCatch", "HoursFished", "TripStatus")
  paths <- canonical_csv(iv)
  conn <- creel_connect(paths, tidycreel::creel_schema(
    survey_type       = "instantaneous",
    interview_uid_col = "InterviewID",
    date_col          = "SurveyDate",
    catch_col         = "TotalCatch",
    effort_col        = "HoursFished",
    trip_status_col   = "TripStatus"
  ))
  msg <- paste(capture.output(fetch_interviews(conn), type = "message"), collapse = " ")
  expect_no_match(msg, "canonical name")
})

test_that("an explicit mapping that finds nothing is still a drop", {
  skip_if_not_installed("withr")
  # The source calls it `date`; the schema says `SurveyDate`, which is not
  # there. Rescuing it from the canonical name would silently paper over a
  # profile that names the wrong column.
  paths <- canonical_csv(canonical_interviews())
  conn <- creel_connect(paths, tidycreel::creel_schema(
    survey_type = "instantaneous",
    date_col    = "SurveyDate"
  ))
  expect_error(suppressMessages(fetch_interviews(conn)), "date")
})
