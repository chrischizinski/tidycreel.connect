# The time of a count, through the fetch layer (GH #129).
#
# A count row is one observation at one moment, not a day's total, and sources
# routinely record several counts on a sampled day. The time is the only thing
# that tells those rows apart. Before this, no schema field could name it and
# neither counts rename map carried it, so the rows reached add_counts() as
# separate sampled days: the day's effort was summed rather than averaged to a
# daily mean, and the within-day variance component was never computed.
#
# These tests pin the column arriving with the source's own values row for row,
# because a count time that is present but recycled would silently collapse the
# distinction it exists to preserve.

make_count_time_csv <- function(count_time = c("16:30", "17:53", "16:05", "18:20")) {
  dir <- withr::local_tempdir(.local_envir = parent.frame())

  # Two counts on each of two dates -- the ordinary shape, not an error.
  counts <- data.frame(
    date          = as.Date(c("2024-06-01", "2024-06-01", "2024-06-02", "2024-06-02")),
    CountTime     = count_time,
    DayType       = c("weekday", "weekday", "weekend", "weekend"),
    bank_anglers  = c(12, 4, 8, 2),
    angler_boats  = c(0, 0, 0, 0),
    non_ang_boats = c(0, 0, 0, 0),
    stringsAsFactors = FALSE
  )
  interviews <- data.frame(
    interview_uid = 1L:2L,
    date          = as.Date(c("2024-06-01", "2024-06-02")),
    DayType       = c("weekday", "weekend"),
    catch_count   = c(3, 1),
    effort_hours  = c(2.5, 2.0),
    trip_status   = rep("complete", 2L),
    stringsAsFactors = FALSE
  )
  catch <- data.frame(
    catch_uid = 1L, interview_uid = 1L, species = "walleye",
    catch_count = 2L, catch_type = "harvested", stringsAsFactors = FALSE
  )
  lengths <- data.frame(
    length_uid = 1L, interview_uid = 1L, species = "walleye",
    length_mm = 450, length_type = "harvest", stringsAsFactors = FALSE
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

make_count_time_schema <- function(count_time_col = "CountTime") {
  tidycreel::creel_schema(
    survey_type       = "instantaneous",
    interview_uid_col = "interview_uid",
    date_col          = "date",
    catch_col         = "catch_count",
    effort_col        = "effort_hours",
    trip_status_col   = "trip_status",
    count_time_col    = count_time_col,
    bank_anglers_col  = "bank_anglers",
    angler_boats_col  = "angler_boats",
    non_ang_boats_col = "non_ang_boats",
    strata_cols       = c(day_type = "DayType")
  )
}

# --- CSV backend ---

test_that("fetch_counts() carries a mapped count time (GH #129)", {
  conn   <- creel_connect(make_count_time_csv(), make_count_time_schema())
  counts <- suppressMessages(fetch_counts(conn))

  expect_true("count_time" %in% names(counts))
  # The source's own labels, row for row: a recycled or first-taken column
  # would collapse the two counts it exists to distinguish.
  expect_equal(counts$count_time, c("16:30", "17:53", "16:05", "18:20"))
})

test_that("a count time is carried as a label, not parsed into a time", {
  # Sources write clock times in whatever format they please. Parsing here
  # would bake one deployment's format in and turn every other one into NA;
  # add_counts() only needs values that differ.
  conn <- creel_connect(
    make_count_time_csv(count_time = c("16:30:00:000", "17:53:00:000", "am", "pm")),
    make_count_time_schema()
  )
  counts <- suppressMessages(fetch_counts(conn))

  expect_type(counts$count_time, "character")
  expect_equal(counts$count_time, c("16:30:00:000", "17:53:00:000", "am", "pm"))
  expect_false(anyNA(counts$count_time))
})

test_that("an unmapped count time is dropped, and said so", {
  # Carrying it is opt-in: without the schema field the closed rename map
  # behaves as before. Pinned rather than left implicit, because this is the
  # state every existing schema is in.
  conn <- creel_connect(make_count_time_csv(), make_count_time_schema(count_time_col = NULL))

  expect_message(
    counts <- suppressWarnings(fetch_counts(conn)),
    "CountTime"
  )
  expect_false("count_time" %in% names(counts))
})

# --- the warning ---

test_that("repeat rows on a date warn when no count time was mapped (GH #129)", {
  # add_counts()'s own CNT-06 tells the caller to supply count_time_col -- a
  # column the fetch layer has just dropped, so the advice cannot be followed
  # from a fetched frame. This names the schema field that makes it reachable.
  conn <- creel_connect(make_count_time_csv(), make_count_time_schema(count_time_col = NULL))

  expect_warning(
    suppressMessages(fetch_counts(conn)),
    "count time"
  )
})

test_that("the warning names count_time_col as the fix", {
  conn <- creel_connect(make_count_time_csv(), make_count_time_schema(count_time_col = NULL))

  expect_warning(
    suppressMessages(fetch_counts(conn)),
    "count_time_col"
  )
})

test_that("mapping the count time silences the warning", {
  conn <- creel_connect(make_count_time_csv(), make_count_time_schema())

  expect_no_warning(suppressMessages(fetch_counts(conn)))
})

test_that("one row per date does not warn", {
  paths  <- make_count_time_csv()
  counts <- utils::read.csv(paths$counts, stringsAsFactors = FALSE)
  counts <- counts[c(1L, 3L), ]
  utils::write.csv(counts, paths$counts, row.names = FALSE)

  conn <- creel_connect(paths, make_count_time_schema(count_time_col = NULL))
  expect_no_warning(suppressMessages(fetch_counts(conn)))
})

test_that("rows sharing a date in different strata are not a repeat", {
  # Two sections counted on one day are two sampling units, not one day counted
  # twice. Keyed the way add_counts() keys its own unit, so this is silent.
  paths  <- make_count_time_csv()
  counts <- utils::read.csv(paths$counts, stringsAsFactors = FALSE)
  counts$DayType <- c("north", "south", "north", "south")
  utils::write.csv(counts, paths$counts, row.names = FALSE)

  conn <- creel_connect(paths, make_count_time_schema(count_time_col = NULL))
  expect_no_warning(suppressMessages(fetch_counts(conn)))
})

test_that("the warning counts the repeat rows and pluralises both ways", {
  # cli evaluates {?s} against the one quantity in the string; a message that is
  # only ever seen with n > 1 hides a broken singular. Both are exercised here.
  paths  <- make_count_time_csv()
  counts <- utils::read.csv(paths$counts, stringsAsFactors = FALSE)
  utils::write.csv(counts[1L:3L, ], paths$counts, row.names = FALSE)

  conn <- creel_connect(paths, make_count_time_schema(count_time_col = NULL))
  expect_warning(suppressMessages(fetch_counts(conn)), "^1 count row repeats")

  utils::write.csv(counts, paths$counts, row.names = FALSE)
  conn <- creel_connect(paths, make_count_time_schema(count_time_col = NULL))
  expect_warning(suppressMessages(fetch_counts(conn)), "^2 count rows repeat ")
})

# --- the handoff this was blocking ---

test_that("a fetched count time reaches add_counts() and averages the day (GH #129)", {
  # The whole point. Without the column these four rows are four sampled days
  # and the effort is their sum; with it they are two days, each the mean of two
  # looks, and the within-day variance component exists.
  conn   <- creel_connect(make_count_time_csv(), make_count_time_schema())
  counts <- suppressMessages(fetch_counts(conn))

  calendar <- data.frame(
    date     = as.Date(c("2024-06-01", "2024-06-02")),
    day_type = c("weekday", "weekend"),
    stringsAsFactors = FALSE
  )
  design <- tidycreel::creel_design(
    calendar = calendar, date = date, strata = day_type,
    survey_type = "instantaneous"
  )
  design <- suppressWarnings(tidycreel::add_counts(
    design, counts,
    count_col      = bank_anglers,
    count_time_col = count_time
  ))

  # Two PSUs, not four: 2024-06-01 is (12 + 4) / 2 = 8, 2024-06-02 is (8 + 2) / 2 = 5.
  expect_equal(nrow(design$counts), 2L)
  expect_equal(sort(design$counts$bank_anglers), c(5, 8))

  # And the within-day component the whole exercise exists to preserve.
  expect_false(is.null(design$within_day_var))
  expect_equal(design$within_day_var$k_d, c(2L, 2L))
})

test_that("the same frame without a count time sums the day instead", {
  # The defect, pinned as the contrast. Four rows survive as four sampling
  # units, the day is never averaged, and no within-day component is computed.
  conn   <- creel_connect(make_count_time_csv(), make_count_time_schema(count_time_col = NULL))
  counts <- suppressWarnings(suppressMessages(fetch_counts(conn)))

  calendar <- data.frame(
    date     = as.Date(c("2024-06-01", "2024-06-02")),
    day_type = c("weekday", "weekend"),
    stringsAsFactors = FALSE
  )
  design <- tidycreel::creel_design(
    calendar = calendar, date = date, strata = day_type,
    survey_type = "instantaneous"
  )
  design <- suppressWarnings(tidycreel::add_counts(design, counts, count_col = bank_anglers))

  expect_equal(nrow(design$counts), 4L)
  expect_null(design$within_day_var)
})
