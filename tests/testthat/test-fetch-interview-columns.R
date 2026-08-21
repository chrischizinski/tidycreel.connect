# Optional interview columns and dropped-column reporting (GH #126)
#
# The rename maps are closed lists and everything outside them is discarded.
# That policy is fine; the defect was that party size, angler type and the
# bus-route join columns had no entry at all, so a fetched design could not be
# handed to add_interviews() for a bus route, and party-hours were consumed as
# angler-hours everywhere else. Neither loss raised anything.

# Fixture: an interviews table carrying every optional column, plus one column
# (weather) that is deliberately unmapped so the drop report has something to say.
make_optional_cols_csv <- function() {
  dir <- withr::local_tempdir(.local_envir = parent.frame())

  interviews <- data.frame(
    interview_uid = 1L:4L,
    date          = as.Date(c("2024-06-01", "2024-06-01", "2024-06-02", "2024-06-02")),
    site          = c("North", "North", "South", "South"),
    circuit       = rep("circuit1", 4L),
    effort_hours  = c(2.5, 1.0, 3.0, 2.0),
    catch_count   = c(3L, 0L, 4L, 1L),
    n_anglers     = c(2L, 1L, 3L, 2L),
    angler_type   = c("boat", "bank", "boat", "boat"),
    n_counted     = c(8L, 8L, 6L, 6L),
    n_interviewed = c(4L, 4L, 3L, 3L),
    trip_status   = rep("complete", 4L),
    weather       = c("clear", "clear", "windy", "windy"),
    stringsAsFactors = FALSE
  )
  counts <- data.frame(
    date          = as.Date(c("2024-06-01", "2024-06-02")),
    bank_anglers  = c(12L, 8L),
    angler_boats  = c(3L, 2L),
    non_ang_boats = c(0L, 0L),
    stringsAsFactors = FALSE
  )
  catch <- data.frame(
    catch_uid     = 1L:2L,
    interview_uid = c(1L, 1L),
    species       = c("walleye", "walleye"),
    catch_count   = c(2L, 1L),
    catch_type    = c("harvest", "release"),
    stringsAsFactors = FALSE
  )
  lengths <- data.frame(
    length_uid    = 1L,
    interview_uid = 1L,
    species       = "walleye",
    length_mm     = 450,
    length_type   = "harvest",
    stringsAsFactors = FALSE
  )

  paths <- list(
    interviews      = file.path(dir, "interviews.csv"),
    counts          = file.path(dir, "counts.csv"),
    catch           = file.path(dir, "catch.csv"),
    harvest_lengths = file.path(dir, "harvest_lengths.csv"),
    release_lengths = file.path(dir, "release_lengths.csv")
  )
  utils::write.csv(interviews, paths$interviews, row.names = FALSE)
  utils::write.csv(counts, paths$counts, row.names = FALSE)
  utils::write.csv(catch, paths$catch, row.names = FALSE)
  utils::write.csv(lengths, paths$harvest_lengths, row.names = FALSE)
  utils::write.csv(lengths, paths$release_lengths, row.names = FALSE)
  paths
}

make_optional_cols_schema <- function() {
  tidycreel::creel_schema(
    survey_type       = "bus_route",
    interview_uid_col = "interview_uid",
    date_col          = "date",
    catch_col         = "catch_count",
    effort_col        = "effort_hours",
    trip_status_col   = "trip_status",
    n_anglers_col     = "n_anglers",
    angler_type_col   = "angler_type",
    site_col          = "site",
    circuit_col       = "circuit",
    n_counted_col     = "n_counted",
    n_interviewed_col = "n_interviewed",
    bank_anglers_col  = "bank_anglers",
    angler_boats_col  = "angler_boats",
    non_ang_boats_col = "non_ang_boats",
    catch_uid_col     = "catch_uid",
    species_col       = "species",
    catch_count_col   = "catch_count",
    catch_type_col    = "catch_type",
    length_uid_col    = "length_uid",
    length_mm_col     = "length_mm",
    length_type_col   = "length_type"
  )
}

# --- CSV backend ---

test_that("fetch_interviews() carries party size and angler type when mapped (GH #126)", {
  # Without these two the fetched frame cannot feed mean_party_size() at all,
  # and add_interviews() silently assumes one angler per interview.
  conn <- creel_connect(make_optional_cols_csv(), make_optional_cols_schema())
  result <- suppressMessages(fetch_interviews(conn))

  expect_true(all(c("n_anglers", "angler_type") %in% names(result)))
  expect_equal(result$n_anglers, c(2, 1, 3, 2))
  expect_true(is.numeric(result$n_anglers))
  expect_true(is.character(result$angler_type))
})

test_that("fetch_interviews() carries the bus-route join columns when mapped (GH #126)", {
  # add_interviews() joins the site inclusion probability on site + circuit;
  # dropping them turned a bus-route handoff into an abort at the pi_i join.
  conn <- creel_connect(make_optional_cols_csv(), make_optional_cols_schema())
  result <- suppressMessages(fetch_interviews(conn))

  expect_true(all(c("site", "circuit", "n_counted", "n_interviewed") %in% names(result)))
  expect_equal(result$site, c("North", "North", "South", "South"))
  expect_true(is.numeric(result$n_counted))
  expect_true(is.numeric(result$n_interviewed))
})

test_that("fetch_interviews() names the source columns it did not carry (GH #126)", {
  # The point of the message is that it names them: a dropped column the caller
  # never needed and a dropped column the estimator needed look identical
  # otherwise.
  conn <- creel_connect(make_optional_cols_csv(), make_optional_cols_schema())

  expect_message(fetch_interviews(conn), "weather")
  expect_message(fetch_interviews(conn), "interviews")
})

test_that("mapped columns are absent from the dropped-column report (GH #126)", {
  conn <- creel_connect(make_optional_cols_csv(), make_optional_cols_schema())
  msg <- paste(
    utils::capture.output(fetch_interviews(conn), type = "message"),
    collapse = " "
  )

  expect_false(grepl("circuit", msg, fixed = TRUE))
  expect_false(grepl("n_anglers", msg, fixed = TRUE))
})

test_that("a fetch that carries everything reports nothing (GH #126)", {
  # A message on every fetch regardless of outcome would be noise, and noise is
  # what let the original drops go unnoticed.
  paths  <- make_test_csv()
  schema <- make_test_schema()
  conn   <- creel_connect(paths, schema)

  expect_no_message(fetch_interviews(conn))
})

test_that("unmapped optional columns are simply absent, not NA (GH #126)", {
  # Absence means "this source does not record party size"; an NA column would
  # claim it does and that every value is missing.
  paths  <- make_optional_cols_csv()
  schema <- make_test_schema() # maps none of the optional columns
  conn   <- creel_connect(paths, schema)
  result <- suppressMessages(fetch_interviews(conn))

  expect_false("n_anglers" %in% names(result))
  expect_false("site" %in% names(result))
})

# --- validation ---

test_that("optional interview columns are type-checked when present (GH #126)", {
  # "Optional" must not mean "unchecked": a character party size would pass a
  # bare-presence test and fail inside the party-size arithmetic much later.
  df <- data.frame(
    interview_uid = "A1",
    date          = as.Date("2024-06-01"),
    catch_count   = 1,
    effort        = 2.5,
    trip_status   = "complete",
    n_anglers     = "2", # character: wrong
    stringsAsFactors = FALSE
  )

  expect_error(
    tidycreel.connect:::validate_fetch_interviews(df),
    "n_anglers"
  )
})

test_that("optional interview columns pass validation when absent (GH #126)", {
  df <- data.frame(
    interview_uid = "A1",
    date          = as.Date("2024-06-01"),
    catch_count   = 1,
    effort        = 2.5,
    trip_status   = "complete",
    stringsAsFactors = FALSE
  )

  expect_silent(tidycreel.connect:::validate_fetch_interviews(df))
})

# --- API backend ---

# Field names below are invented. No default names a party-size, site or
# circuit field, so an API backend reaches these columns only by being told
# which raw fields hold them.
api_conn_with_map <- function(field_map) {
  creel_connect_api(
    base_url      = "http://test.example.com/api/",
    creel_uids    = "test-uid-001",
    schema        = tidycreel::creel_schema(survey_type = "bus_route"),
    api_field_map = list(interviews = field_map)
  )
}

test_that("api_field_map routes party size and angler type (GH #126)", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body    = charToRaw(paste0(
        '[{"InterviewID":"A1","SurveyDate":"2016-03-28","TripStatus":"complete",',
        '"HoursFished":2,"MinutesFished":30,',
        '"NumberAnglers":3,"AnglerType":2}]'
      ))
    )
  })
  conn <- api_conn_with_map(list(
    interview_uid  = "InterviewID",
    date           = "SurveyDate",
    trip_status    = "TripStatus",
    effort_hours   = "HoursFished",
    effort_minutes = "MinutesFished",
    n_anglers      = "NumberAnglers",
    angler_type    = "AnglerType"
  ))
  result <- suppressMessages(fetch_interviews(conn))

  expect_equal(result$n_anglers, 3)
  expect_true(is.numeric(result$n_anglers))
  # A source that codes angler type as an integer still means a category:
  # character keeps arithmetic from consuming the code as a quantity.
  expect_equal(result$angler_type, "2")
})

test_that("api_field_map routes bus-route interview columns (GH #126)", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body    = charToRaw(paste0(
        '[{"InterviewID":"A1","SurveyDate":"2016-03-28","TripStatus":"complete",',
        '"HoursFished":2,"MinutesFished":0,',
        '"SiteName":"North","Route":"circuit1","Seen":8,"Asked":4}]'
      ))
    )
  })
  conn <- api_conn_with_map(list(
    interview_uid  = "InterviewID",
    date           = "SurveyDate",
    trip_status    = "TripStatus",
    effort_hours   = "HoursFished",
    effort_minutes = "MinutesFished",
    site           = "SiteName",
    circuit        = "Route",
    n_counted      = "Seen",
    n_interviewed  = "Asked"
  ))
  result <- suppressMessages(fetch_interviews(conn))

  expect_equal(result$site, "North")
  expect_equal(result$circuit, "circuit1")
  expect_equal(result$n_counted, 8)
  expect_equal(result$n_interviewed, 4)
})

# --- composition ---

test_that("a fetched party size reaches the effort SE (GH #126)", {
  # The whole point of the routing change: fetch -> mean_party_size() ->
  # derive_angler_count() -> add_counts() -> estimate_effort(), with the
  # party-size standard error still attached at the end. Before, the fetched
  # frame had no n_anglers column, so this chain could not start.
  conn       <- creel_connect(make_optional_cols_csv(), make_optional_cols_schema())
  interviews <- suppressMessages(fetch_interviews(conn))
  counts     <- suppressMessages(fetch_counts(conn))

  ps <- tidycreel::mean_party_size(
    interviews,
    n_anglers   = n_anglers,
    angler_type = angler_type,
    boat_value  = "boat"
  )
  expect_gt(as.numeric(ps), 1) # boats really do carry more than one angler here

  counts <- tidycreel::derive_angler_count(
    counts,
    bank          = bank_anglers,
    boat_count    = angler_boats,
    party_size    = ps,
    party_size_se = attr(ps, "se")
  )

  calendar <- data.frame(
    date     = as.Date(c("2024-06-01", "2024-06-02")),
    day_type = "weekday",
    stringsAsFactors = FALSE
  )
  # The counts rename map carries no stratum label, so the caller attaches it.
  # add_counts() requires the design's strata columns to be present in counts.
  counts <- merge(counts, calendar, by = "date")

  design <- suppressWarnings(tidycreel::creel_design(
    calendar,
    date   = date,
    strata = day_type
  ))
  design <- suppressWarnings(suppressMessages(tidycreel::add_counts(
    design,
    counts,
    count_col = "angler_count"
  )))
  design <- suppressWarnings(suppressMessages(tidycreel::add_interviews(
    design,
    interviews,
    catch       = catch_count,
    effort      = effort,
    trip_status = trip_status,
    n_anglers   = n_anglers
  )))

  effort <- suppressWarnings(suppressMessages(tidycreel::estimate_effort(design)))

  # NULL would mean the term never propagated, and 0 would be indistinguishable
  # from a party size known exactly.
  expect_false(is.null(effort$se_expansion))
  expect_true(all(effort$se_expansion > 0))
})

test_that("the API fetch does not report the effort fields as dropped (GH #126)", {
  # The two effort fields are consumed by arithmetic rather than renamed, so
  # they are carried, not lost. Reporting them as dropped would train the reader
  # to ignore the message -- and the message is the whole safeguard.
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body    = charToRaw(paste0(
        '[{"InterviewID":"A1","SurveyDate":"2016-03-28","TripStatus":"complete",',
        '"HoursFished":2,"MinutesFished":30,"Refused":false}]'
      ))
    )
  })
  conn <- api_conn_with_map(list(
    interview_uid  = "InterviewID",
    date           = "SurveyDate",
    trip_status    = "TripStatus",
    effort_hours   = "HoursFished",
    effort_minutes = "MinutesFished"
  ))
  msg <- paste(
    utils::capture.output(fetch_interviews(conn), type = "message"),
    collapse = " "
  )

  expect_false(grepl("HoursFished", msg, fixed = TRUE))
  expect_false(grepl("MinutesFished", msg, fixed = TRUE))
  expect_true(grepl("Refused", msg, fixed = TRUE))
})
