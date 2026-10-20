# The interview summary columns (tidycreel.connect#3)
#
# angler_method, species_sought, refused and zip_code are what tidycreel's
# unextrapolated summaries read. fetch_interviews() had no entry for any of
# them, so a field named in api_field_map was still dropped and an agency
# report needed a second, raw fetch. refused matters beyond its summary: a
# refused interview has unknown catch, and without the flag it reaches the
# design looking like a no-catch party.

# Field names below are invented, as in test-fetch-interview-columns.R.
summary_api_conn <- function(field_map) {
  make_api_conn(
    field_map = list(interviews = field_map),
    endpoints = list(interviews = "v2/interviews"),
    schema    = tidycreel::creel_schema(survey_type = "instantaneous")
  )
}

summary_field_map <- function() {
  list(
    interview_uid  = "InterviewID",
    date           = "SurveyDate",
    trip_status    = "TripStatus",
    effort_hours   = "HoursFished",
    effort_minutes = "MinutesFished",
    angler_method  = "Method",
    species_sought = "Target",
    refused        = "Refused",
    zip_code       = "Zip"
  )
}

mock_interviews_json <- function(rows) {
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body    = charToRaw(paste0("[", paste(rows, collapse = ","), "]"))
    )
  }, env = parent.frame())
}

summary_row <- function(id, date, method, target, refused, zip, hours = 2) {
  sprintf(
    paste0(
      '{"InterviewID":"%s","SurveyDate":"%s","TripStatus":"complete",',
      '"HoursFished":%s,"MinutesFished":0,"Method":%s,"Target":"%s",',
      '"Refused":%s,"Zip":%s}'
    ),
    id, date, hours, method, target, refused, zip
  )
}

# --- API backend ---

test_that("api_field_map carries the four summary fields (tidycreel.connect#3)", {
  # Named in the map, they used to land in "not carried through" -- the defect.
  mock_interviews_json(c(
    summary_row("A1", "2016-03-28", 1, "walleye", '"Y"', 6810),
    summary_row("A2", "2016-03-28", 2, "anything", '"N"', 68502)
  ))
  conn <- summary_api_conn(summary_field_map())
  msg <- paste(
    utils::capture.output(result <- fetch_interviews(conn), type = "message"),
    collapse = " "
  )

  expect_true(all(c("angler_method", "species_sought", "refused", "zip_code") %in% names(result)))
  for (field in c("Method", "Target", "Refused", "Zip")) {
    expect_false(grepl(field, msg, fixed = TRUE))
  }
})

test_that("a coded refusal flag arrives as logical (tidycreel.connect#3)", {
  # summarize_refusals() splits on ifelse(refused, ...): a character "Y" reads
  # as NA there, so every refusal would drop out of the table without a word.
  mock_interviews_json(c(
    summary_row("A1", "2016-03-28", 1, "walleye", '"Y"', 68502),
    summary_row("A2", "2016-03-28", 1, "walleye", '"n"', 68502),
    summary_row("A3", "2016-03-28", 1, "walleye", "1", 68502),
    summary_row("A4", "2016-03-28", 1, "walleye", "false", 68502),
    summary_row("A5", "2016-03-28", 1, "walleye", '""', 68502)
  ))
  result <- suppressMessages(fetch_interviews(summary_api_conn(summary_field_map())))

  expect_type(result$refused, "logical")
  # A blank is a missing flag, not a refusal and not a code to refuse.
  expect_identical(result$refused, c(TRUE, FALSE, TRUE, FALSE, NA))
})

test_that("an unreadable refusal code aborts and names it (tidycreel.connect#3)", {
  # Silently reading "maybe" as NA is exactly the loss this guards against.
  mock_interviews_json(c(
    summary_row("A1", "2016-03-28", 1, "walleye", '"maybe"', 68502),
    summary_row("A2", "2016-03-28", 1, "walleye", '"Y"', 68502)
  ))
  conn <- summary_api_conn(summary_field_map())

  expect_error(suppressMessages(fetch_interviews(conn)), "maybe")
})

test_that("a numeric ZIP keeps its leading zero (tidycreel.connect#3)", {
  # Served as a JSON number, 06810 parses to 6810; tabulated as-is it would be a
  # different ZIP from the "06810" a text source writes for the same angler.
  mock_interviews_json(c(
    summary_row("A1", "2016-03-28", 1, "walleye", "false", 6810),
    summary_row("A2", "2016-03-28", 1, "walleye", "false", 68502),
    summary_row("A3", "2016-03-28", 1, "walleye", "false", "null")
  ))
  result <- suppressMessages(fetch_interviews(summary_api_conn(summary_field_map())))

  expect_identical(result$zip_code, c("06810", "68502", NA))
})

test_that("method and species codes are carried as labels (tidycreel.connect#3)", {
  # A method coded 1/2 is a category: summarize_by_method() groups on it, and
  # character keeps arithmetic from consuming the code as a quantity.
  mock_interviews_json(summary_row("A1", "2016-03-28", 2, "walleye", "false", 68502))
  result <- suppressMessages(fetch_interviews(summary_api_conn(summary_field_map())))

  expect_identical(result$angler_method, "2")
  expect_identical(result$species_sought, "walleye")
})

test_that("unmapped summary fields stay absent (tidycreel.connect#3)", {
  # Opt-in, like the other optional interview columns: no default names them.
  mock_interviews_json(summary_row("A1", "2016-03-28", 1, "walleye", "false", 68502))
  fm <- summary_field_map()
  fm[c("angler_method", "species_sought", "refused", "zip_code")] <- NULL
  result <- suppressMessages(fetch_interviews(summary_api_conn(fm)))

  expect_false(any(c("angler_method", "species_sought", "refused", "zip_code") %in% names(result)))
})

# --- CSV backend ---

test_that("creel_schema() routes method, species and refusal on CSV (tidycreel.connect#3)", {
  dir <- withr::local_tempdir()
  interviews <- data.frame(
    interview_uid = 1L:3L,
    date          = as.Date(c("2024-06-01", "2024-06-01", "2024-06-02")),
    effort_hours  = c(2.5, 1.0, 3.0),
    catch_count   = c(3L, 0L, 4L),
    trip_status   = rep("complete", 3L),
    Method        = c("boat", "bank", "boat"),
    Target        = c("walleye", "anything", "walleye"),
    Refused       = c("N", "Y", "N"),
    zip_code      = c("06810", "68502", NA),
    stringsAsFactors = FALSE
  )
  paths <- make_test_csv()
  paths$interviews <- file.path(dir, "interviews.csv")
  utils::write.csv(interviews, paths$interviews, row.names = FALSE)
  schema <- tidycreel::creel_schema(
    survey_type        = "instantaneous",
    interview_uid_col  = "interview_uid",
    date_col           = "date",
    catch_col          = "catch_count",
    effort_col         = "effort_hours",
    trip_status_col    = "trip_status",
    angler_method_col  = "Method",
    species_sought_col = "Target",
    refused_col        = "Refused"
  )

  result <- suppressMessages(fetch_interviews(creel_connect(paths, schema)))

  expect_identical(result$angler_method, c("boat", "bank", "boat"))
  expect_identical(result$species_sought, c("walleye", "anything", "walleye"))
  expect_identical(result$refused, c(FALSE, TRUE, FALSE))
  # creel_schema() has no zip_code_col: the column is taken by its canonical
  # name, and readr's numeric guess must not cost it the leading zero.
  expect_identical(result$zip_code, c("06810", "68502", NA))
})

# --- validation ---

test_that("a character refusal flag fails validation (tidycreel.connect#3)", {
  df <- data.frame(
    interview_uid = "A1",
    date          = as.Date("2024-06-01"),
    catch_count   = 1,
    effort        = 2.5,
    trip_status   = "complete",
    refused       = "Y",
    stringsAsFactors = FALSE
  )

  expect_error(tidycreel.connect:::validate_fetch_interviews(df), "refused")
})

# --- composition ---

test_that("a fetched refusal flag reaches summarize_refusals() (tidycreel.connect#3)", {
  # The report this issue came from: fetch -> add_interviews(refused =) ->
  # summarize_refusals(), with no second raw fetch in between.
  mock_interviews_json(c(
    summary_row("A1", "2016-03-28", 1, "walleye", '"Y"', 68502),
    summary_row("A2", "2016-03-28", 1, "walleye", '"N"', 68502),
    summary_row("A3", "2016-03-29", 1, "walleye", '"N"', 68502)
  ))
  interviews <- suppressMessages(fetch_interviews(summary_api_conn(summary_field_map())))
  interviews$catch_count <- c(NA, 2, 0)

  calendar <- data.frame(
    date     = as.Date(c("2016-03-28", "2016-03-29")),
    day_type = "weekday",
    stringsAsFactors = FALSE
  )
  design <- suppressWarnings(tidycreel::creel_design(calendar, date = date, strata = day_type))
  design <- suppressWarnings(suppressMessages(tidycreel::add_interviews(
    design,
    interviews,
    catch       = catch_count,
    effort      = effort,
    trip_status = trip_status,
    refused     = refused
  )))

  refusals <- tidycreel::summarize_refusals(design)
  n_refused <- sum(refusals$N[refusals$participation == "refused"])
  n_accepted <- sum(refusals$N[refusals$participation == "accepted"])
  expect_equal(n_refused, 1)
  expect_equal(n_accepted, 2)
})
