# Binned release lengths through the fetch layer (GH #127).
#
# A binned length row is frequency-weighted: a row saying "350-400, 5 fish" is
# five fish, not one. The fetch layer carried no count column at all, so every
# binned source arrived one-row-per-bin and any distribution built from it was
# weighted by row multiplicity instead of by fish -- a believable number, no
# error, no warning. It also had nowhere to put a bin label except `length_mm`,
# where .coerce_numeric() turned it into NA, or where it silently rested a
# millimetre unit on a group label.
#
# These tests pin the fish-count arithmetic end to end, not just the presence of
# the columns: a count that is carried but ignored looks identical at the seam.

make_binned_csv <- function(release = NULL) {
  dir <- withr::local_tempdir(.local_envir = parent.frame())

  interviews <- data.frame(
    interview_uid = 1L:2L,
    date          = as.Date(c("2024-06-01", "2024-06-02")),
    catch_count   = c(6L, 0L),
    effort_hours  = c(2.5, 1.0),
    trip_status   = rep("complete", 2L),
    stringsAsFactors = FALSE
  )
  counts <- data.frame(
    date          = as.Date(c("2024-06-01", "2024-06-02")),
    bank_anglers  = c(12L, 8L),
    stringsAsFactors = FALSE
  )
  catch <- data.frame(
    catch_uid     = 1L,
    interview_uid = 1L,
    species       = "walleye",
    catch_count   = 6L,
    catch_type    = "release",
    stringsAsFactors = FALSE
  )
  harvest <- data.frame(
    length_uid    = 1L,
    interview_uid = 1L,
    species       = "walleye",
    LengthMM      = 450.0,
    length_type   = "harvest",
    stringsAsFactors = FALSE
  )
  # Two bins holding different numbers of fish. 1 and 5 are chosen so that
  # fish-weighted (6) and row-weighted (2) totals cannot coincide, and so that
  # the two bins are not interchangeable.
  if (is.null(release)) {
    release <- data.frame(
      length_uid    = 1L:2L,
      interview_uid = c(1L, 1L),
      species       = c("walleye", "walleye"),
      LengthBand   = c("300-350", "350-400"),
      GroupCount    = c(1L, 5L),
      length_type   = rep("release", 2L),
      stringsAsFactors = FALSE
    )
  }

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
  utils::write.csv(harvest, paths$harvest_lengths, row.names = FALSE)
  utils::write.csv(release, paths$release_lengths, row.names = FALSE)
  paths
}

make_binned_schema <- function(...) {
  args <- list(
    survey_type       = "instantaneous",
    interview_uid_col = "interview_uid",
    date_col          = "date",
    catch_col         = "catch_count",
    effort_col        = "effort_hours",
    trip_status_col   = "trip_status",
    bank_anglers_col  = "bank_anglers",
    species_col       = "species",
    length_uid_col    = "length_uid",
    length_mm_col     = "LengthMM",
    length_bin_col    = "LengthBand",
    length_count_col  = "GroupCount",
    length_type_col   = "length_type"
  )
  args <- utils::modifyList(args, list(...))
  do.call(tidycreel::creel_schema, args)
}

# --- CSV backend ---

test_that("fetch_release_lengths() carries the bin label and its fish count (GH #127)", {
  conn <- creel_connect(make_binned_csv(), make_binned_schema())
  rel <- suppressMessages(fetch_release_lengths(conn))

  expect_true(all(c("length_bin", "count") %in% names(rel)))
  # The label survives as a label -- not coerced, not rounded, not NA.
  expect_identical(rel$length_bin, c("300-350", "350-400"))
  expect_true(is.character(rel$length_bin))
  # And the counts are the source's own, row for row.
  expect_equal(rel$count, c(1, 5))
})

test_that("a bin label is never routed into length_mm", {
  # Mapping the label as a measurement is the old behaviour: .coerce_numeric()
  # turns "300-350" into NA and warns, leaving a column named _mm whose unit
  # came from nowhere. length_mm must simply be absent for a binned source.
  conn <- creel_connect(make_binned_csv(), make_binned_schema())
  rel <- suppressMessages(fetch_release_lengths(conn))

  expect_false("length_mm" %in% names(rel))
})

test_that("harvest lengths carry the count column too", {
  # Symmetry is the point: the harvest/release asymmetry is what disguised the
  # bug. A harvest source that tallies rather than measures can say so.
  conn <- creel_connect(make_binned_csv(), make_binned_schema())
  harv <- suppressMessages(fetch_harvest_lengths(conn))

  expect_true("length_mm" %in% names(harv))
  expect_equal(harv$length_mm, 450)
})

test_that("a bin carried without a count warns where it happens", {
  paths <- make_binned_csv()
  conn <- creel_connect(paths, make_binned_schema(length_count_col = NULL))

  expect_warning(
    rel <- suppressMessages(fetch_release_lengths(conn)),
    "without a fish count"
  )
  # The bin still arrives; what is refused is doing so silently.
  expect_true("length_bin" %in% names(rel))
  expect_false("count" %in% names(rel))
})

test_that("a lengths table with neither a measurement nor a bin aborts", {
  conn <- creel_connect(
    make_binned_csv(),
    make_binned_schema(length_mm_col = NULL, length_bin_col = NULL)
  )

  expect_error(
    suppressMessages(fetch_release_lengths(conn)),
    "neither"
  )
})

test_that("an unmapped binned pair leaves the measured contract unchanged", {
  # Carrying the pair is opt-in. A source that measures every fish maps neither
  # column and sees exactly the frame it saw before.
  release <- data.frame(
    length_uid    = 1L:2L,
    interview_uid = c(1L, 1L),
    species       = c("walleye", "walleye"),
    LengthMM      = c(320.0, 375.0),
    length_type   = rep("release", 2L),
    stringsAsFactors = FALSE
  )
  conn <- creel_connect(
    make_binned_csv(release = release),
    make_binned_schema(length_bin_col = NULL, length_count_col = NULL)
  )
  rel <- suppressMessages(fetch_release_lengths(conn))

  expect_equal(rel$length_mm, c(320, 375))
  expect_false(any(c("length_bin", "count") %in% names(rel)))
})

# --- the handoff this was blocking ---

test_that("a fetched binned frame weights the distribution by fish, not by rows (GH #127)", {
  # The regression the issue asks for: bins holding 1 and 5 fish must total 6.
  # Before this, the count never left the source and the same data totalled 2 --
  # a plausible number with no error attached to it.
  conn <- creel_connect(make_binned_csv(), make_binned_schema())
  rel <- suppressMessages(fetch_release_lengths(conn))

  interviews <- data.frame(
    interview_uid = 1L:2L,
    date          = as.Date(c("2024-06-01", "2024-06-02")),
    catch_count   = c(6L, 0L),
    effort_hours  = c(2.5, 1.0),
    trip_status   = rep("complete", 2L),
    stringsAsFactors = FALSE
  )
  calendar <- data.frame(
    date     = as.Date(c("2024-06-01", "2024-06-02")),
    day_type = c("weekday", "weekend"),
    stringsAsFactors = FALSE
  )

  design <- suppressWarnings(tidycreel::creel_design(calendar, date = date, strata = day_type))
  design <- suppressWarnings(suppressMessages(tidycreel::add_interviews(
    design,
    interviews,
    catch       = catch_count,
    effort      = effort_hours,
    trip_status = trip_status
  )))
  design <- suppressWarnings(suppressMessages(tidycreel::add_lengths(
    design,
    rel,
    length_uid     = interview_uid,
    interview_uid  = interview_uid,
    species        = species,
    length         = length_bin,
    length_type    = length_type,
    count          = count,
    release_format = "binned"
  )))

  freq <- suppressWarnings(suppressMessages(
    tidycreel::summarize_length_freq(design, type = "release", bin_width = 50)
  ))

  expect_equal(sum(freq$N), 6)
  # And the 5-fish bin is the heavier one, so the weights are not merely summing
  # to the right total by coincidence.
  heaviest <- freq[which.max(freq$N), ]
  expect_equal(heaviest$N, 5)
})

# --- API backend ---

test_that("the API path takes the binned pair from api_field_map (GH #127)", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body = charToRaw(paste0(
        '[{"InterviewID":1,"SpeciesCode":"walleye","LengthBand":"300-350","GroupCount":1},',
        '{"InterviewID":1,"SpeciesCode":"walleye","LengthBand":"350-400","GroupCount":5}]'
      ))
    )
  })
  fm <- test_api_field_map()
  # Raw JSON field names live only here -- never routed through creel_schema().
  fm$release_lengths <- list(
    interview_uid = "InterviewID",
    species       = "SpeciesCode",
    length_bin    = "LengthBand",
    count         = "GroupCount"
  )
  conn <- make_api_conn(
    field_map = fm,
    schema = tidycreel::creel_schema(survey_type = "instantaneous")
  )

  rel <- suppressMessages(fetch_release_lengths(conn))
  expect_identical(rel$length_bin, c("300-350", "350-400"))
  expect_equal(rel$count, c(1, 5))
  expect_equal(rel$length_type, rep("release", 2L))
})

test_that("an empty API response keeps the binned columns when the source has them", {
  # A quiet day must not change the shape of the frame: code that selects
  # length_bin/count would otherwise break only on days with no fish.
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body = charToRaw("[]")
    )
  })
  fm <- test_api_field_map()
  fm$release_lengths <- list(
    interview_uid = "InterviewID",
    species       = "SpeciesCode",
    length_bin    = "LengthBand",
    count         = "GroupCount"
  )
  conn <- make_api_conn(
    field_map = fm,
    schema = tidycreel::creel_schema(survey_type = "instantaneous")
  )

  rel <- suppressMessages(fetch_release_lengths(conn))
  expect_equal(nrow(rel), 0L)
  expect_true(all(c("length_bin", "count") %in% names(rel)))
})

test_that("an empty API response omits the binned columns for a measured source", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body = charToRaw("[]")
    )
  })
  conn <- make_api_conn(schema = tidycreel::creel_schema(survey_type = "instantaneous"))

  rel <- suppressMessages(fetch_release_lengths(conn))
  expect_equal(nrow(rel), 0L)
  expect_false(any(c("length_bin", "count") %in% names(rel)))
})
