# Stratum columns through the fetch layer (GH #171).
#
# A stratum is the one mapped quantity with no canonical tidycreel name:
# add_counts() matches design$strata_cols -- the caller's own calendar column
# names -- against the names of the counts frame. Before this, the rename maps
# carried no stratum at all, so a fetched counts frame reached add_counts() with
# no label and every design built with `strata =` aborted. These tests pin both
# that the column arrives and that it arrives carrying the source's own values,
# because a stratum that is present but recycled is the dangerous failure.

make_strata_csv <- function() {
  dir <- withr::local_tempdir(.local_envir = parent.frame())

  # Two day types, deliberately NOT in a repeating pattern, so a recycled or
  # first-value-taken column is distinguishable from a correctly carried one.
  interviews <- data.frame(
    interview_uid = 1L:4L,
    date          = as.Date(c("2024-06-01", "2024-06-02", "2024-06-03", "2024-06-04")),
    DayType       = c("weekday", "weekend", "weekend", "weekday"),
    catch_count   = c(3L, 0L, 4L, 1L),
    effort_hours  = c(2.5, 1.0, 3.0, 2.0),
    trip_status   = rep("complete", 4L),
    stringsAsFactors = FALSE
  )
  counts <- data.frame(
    date          = as.Date(c("2024-06-01", "2024-06-02", "2024-06-03", "2024-06-04")),
    DayType       = c("weekday", "weekend", "weekend", "weekday"),
    bank_anglers  = c(12L, 8L, 6L, 10L),
    angler_boats  = c(3L, 2L, 1L, 4L),
    non_ang_boats = c(0L, 0L, 0L, 0L),
    stringsAsFactors = FALSE
  )
  # Not exercised here, but creel_connect() requires all five paths.
  catch <- data.frame(
    catch_uid     = 1L,
    interview_uid = 1L,
    species       = "walleye",
    catch_count   = 2L,
    catch_type    = "harvest",
    stringsAsFactors = FALSE
  )
  lengths <- data.frame(
    length_uid    = 1L,
    interview_uid = 1L,
    species       = "walleye",
    length_mm     = 450.0,
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

make_strata_schema <- function(strata_cols = c(day_type = "DayType")) {
  tidycreel::creel_schema(
    survey_type       = "instantaneous",
    interview_uid_col = "interview_uid",
    date_col          = "date",
    catch_col         = "catch_count",
    effort_col        = "effort_hours",
    trip_status_col   = "trip_status",
    bank_anglers_col  = "bank_anglers",
    angler_boats_col  = "angler_boats",
    non_ang_boats_col = "non_ang_boats",
    strata_cols       = strata_cols
  )
}

# --- CSV backend ---

test_that("fetch_counts() carries a mapped stratum under the design's name (GH #171)", {
  conn <- creel_connect(make_strata_csv(), make_strata_schema())
  counts <- suppressMessages(fetch_counts(conn))

  expect_true("day_type" %in% names(counts))
  expect_false("DayType" %in% names(counts))
  # The source's own labels, row for row -- not recycled, not the first value.
  expect_equal(counts$day_type, c("weekday", "weekend", "weekend", "weekday"))
})

test_that("fetch_interviews() carries the stratum too (GH #171)", {
  conn <- creel_connect(make_strata_csv(), make_strata_schema())
  interviews <- suppressMessages(fetch_interviews(conn))

  expect_true("day_type" %in% names(interviews))
  expect_equal(interviews$day_type, c("weekday", "weekend", "weekend", "weekday"))
})

test_that("an unnamed strata_cols entry names itself on both sides", {
  # The source already uses the design's name, so no rename is implied.
  paths <- make_strata_csv()
  counts <- utils::read.csv(paths$counts, stringsAsFactors = FALSE)
  names(counts)[names(counts) == "DayType"] <- "day_type"
  utils::write.csv(counts, paths$counts, row.names = FALSE)

  conn <- creel_connect(paths, make_strata_schema(strata_cols = c("day_type")))
  fetched <- suppressMessages(fetch_counts(conn))

  expect_true("day_type" %in% names(fetched))
  expect_equal(fetched$day_type, c("weekday", "weekend", "weekend", "weekday"))
})

test_that("an unmapped stratum is still dropped, and said so", {
  # Carrying the column is opt-in: without strata_cols the closed rename map
  # behaves as before. This is what made the abort in #171 possible, so it is
  # pinned rather than left implicit.
  conn <- creel_connect(make_strata_csv(), make_strata_schema(strata_cols = NULL))

  expect_message(
    counts <- fetch_counts(conn),
    "DayType"
  )
  expect_false("day_type" %in% names(counts))
})

test_that("mapping a stratum the source does not have drops it rather than inventing one", {
  conn <- creel_connect(
    make_strata_csv(),
    make_strata_schema(strata_cols = c(period = "NotAColumn"))
  )
  counts <- suppressMessages(fetch_counts(conn))

  expect_false("period" %in% names(counts))
})

# --- the handoff this was blocking ---

test_that("a fetched counts frame reaches add_counts() on a stratified design (GH #171)", {
  # The documented path, with no manual re-join. Before this it aborted with
  # "Strata column(s) from design not found in count data: day_type".
  conn   <- creel_connect(make_strata_csv(), make_strata_schema())
  counts <- suppressMessages(fetch_counts(conn))

  counts <- tidycreel::derive_angler_count(
    counts,
    bank       = bank_anglers,
    boat_count = angler_boats,
    party_size = 2.5
  )

  calendar <- data.frame(
    date     = as.Date(c("2024-06-01", "2024-06-02", "2024-06-03", "2024-06-04")),
    day_type = c("weekday", "weekend", "weekend", "weekday"),
    stringsAsFactors = FALSE
  )
  design <- suppressWarnings(tidycreel::creel_design(
    calendar,
    date   = date,
    strata = day_type
  ))

  expect_no_error(
    design <- suppressWarnings(suppressMessages(
      tidycreel::add_counts(design, counts, count_col = "angler_count")
    ))
  )
  # The stratum survives onto the design rather than merely satisfying the check.
  expect_setequal(unique(design$counts$day_type), c("weekday", "weekend"))
})

# --- API backend ---

test_that("the API path takes the stratum's source name from api_field_map", {
  # Raw API field names live only in api_field_map; the design-facing name comes
  # from the schema. The two must not be routed through each other, so the
  # schema here names `day_type` while the payload key is DayTypeCode.
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body = charToRaw(paste0(
        '[{"SurveyDate":"2024-06-01","DayTypeCode":"weekday","ShoreAnglers":12},',
        '{"SurveyDate":"2024-06-02","DayTypeCode":"weekend","ShoreAnglers":8}]'
      ))
    )
  })
  fm <- test_api_field_map()
  fm$counts$day_type <- "DayTypeCode"
  # An API-shaped schema declares only the survey type and the strata: every
  # other column name on this path comes from api_field_map.
  conn <- make_api_conn(
    field_map = fm,
    schema = tidycreel::creel_schema(
      survey_type = "instantaneous",
      strata_cols = c(day_type = "day_type")
    )
  )

  counts <- suppressMessages(fetch_counts(conn))
  expect_true("day_type" %in% names(counts))
  expect_equal(counts$day_type, c("weekday", "weekend"))
})

test_that("an API stratum absent from the field map falls back to its own name", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body = charToRaw(paste0(
        '[{"SurveyDate":"2024-06-01","day_type":"weekday","ShoreAnglers":12},',
        '{"SurveyDate":"2024-06-02","day_type":"weekend","ShoreAnglers":8}]'
      ))
    )
  })
  conn <- make_api_conn(
    schema = tidycreel::creel_schema(
      survey_type = "instantaneous",
      strata_cols = c("day_type")
    )
  )

  counts <- suppressMessages(fetch_counts(conn))
  expect_equal(counts$day_type, c("weekday", "weekend"))
})
