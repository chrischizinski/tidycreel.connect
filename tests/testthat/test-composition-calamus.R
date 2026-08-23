# The ingestion seam, composed end to end (GH #130).
#
# Every other test in this package checks a fetched frame's column names, types
# and values. None of them ran an estimator, so nothing asserted that what the
# fetch layer produces still reproduces a known answer once a design is built on
# it -- which is why #126 through #129 all shipped undetected. Each was a column
# that existed upstream and never reached the calculation, and column-level
# tests cannot see that by construction.
#
# This composes the whole path on the one fixture with validated outputs:
#
#   CSV -> fetch_*() -> creel_design() -> add_counts()/add_interviews()
#       -> estimate_effort() / estimate_total_catch() / estimate_total_harvest()
#
# and asserts the results against inst/extdata/calamus-2016/reference-outputs.csv
# in the tidycreel package. Standard errors are asserted too, not just point
# estimates: an SE is where a dropped component hides, and every uncertainty
# defect this package has shipped left the point estimate untouched.

# lintr: this file is built on tidy-selection, so design and interview column
# names appear as bare symbols inside helper functions -- object_usage_linter
# cannot see that they resolve against a data frame. The prose references issue
# numbers and estimator calls, which commented_code_linter reads as code.
# nolint start: object_usage_linter, commented_code_linter.

calamus_dir <- function() {
  d <- system.file("extdata", "calamus-2016", package = "tidycreel")
  if (!nzchar(d) || !file.exists(file.path(d, "reference-outputs.csv"))) {
    testthat::skip("calamus-2016 fixture not available from the installed tidycreel")
  }
  d
}

calamus_schema <- function() {
  tidycreel::creel_schema(
    survey_type       = "bus_route",
    interview_uid_col = "interview_uid",
    date_col          = "date",
    site_col          = "site",
    circuit_col       = "circuit",
    effort_col        = "effort_hours",
    catch_col         = "catch_count",
    trip_status_col   = "trip_status",
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

calamus_conn <- function(dir = calamus_dir(), counts = file.path(dir, "counts.csv")) {
  creel_connect(
    list(
      interviews      = file.path(dir, "interviews.csv"),
      counts          = counts,
      catch           = file.path(dir, "catch.csv"),
      harvest_lengths = file.path(dir, "harvest_lengths.csv"),
      release_lengths = file.path(dir, "release_lengths.csv")
    ),
    calamus_schema()
  )
}

# The frame the reference outputs were generated against.
calamus_calendar <- function() {
  data.frame(
    date = as.Date(c(
      "2016-06-06", "2016-06-07", "2016-06-08",
      "2016-06-09", "2016-06-10", "2016-06-11", "2016-06-12"
    )),
    day_type = c("weekday", "weekday", "weekday", "weekday", "weekday", "weekend", "weekend"),
    stringsAsFactors = FALSE
  )
}

calamus_frame <- function() {
  data.frame(
    site     = c("North", "South", "Pier"),
    circuit  = "circuit1",
    p_site   = c(0.40, 0.35, 0.25),
    p_period = 0.50,
    stringsAsFactors = FALSE
  )
}

# Harvest per interview, aggregated from the fetched catch table. add_interviews()
# needs it on the interviews frame, and the catch table is where it lives -- this
# is the join the documented workflow asks the caller to make.
attach_harvest <- function(interviews, catch) {
  harvested <- catch[catch$catch_type == "harvested", , drop = FALSE]
  by_uid <- stats::aggregate(catch_count ~ interview_uid, data = harvested, FUN = sum)
  names(by_uid)[2] <- "harvest_count"
  out <- merge(interviews, by_uid, by = "interview_uid", all.x = TRUE)
  out$harvest_count[is.na(out$harvest_count)] <- 0
  out
}

build_calamus_design <- function(conn) {
  interviews <- suppressMessages(fetch_interviews(conn))
  counts     <- suppressMessages(suppressWarnings(fetch_counts(conn)))
  catch      <- suppressMessages(fetch_catch(conn))

  interviews <- attach_harvest(interviews, catch)
  counts <- merge(counts, calamus_calendar()[c("date", "day_type")], by = "date", all.x = TRUE)

  design <- tidycreel::creel_design(
    calendar       = calamus_calendar(),
    date           = date,
    strata         = day_type,
    survey_type    = "bus_route",
    sampling_frame = calamus_frame(),
    site           = site,
    circuit        = circuit,
    p_site         = p_site,
    p_period       = p_period
  )
  design <- suppressWarnings(tidycreel::add_counts(design, counts, count_col = bank_anglers))
  suppressWarnings(tidycreel::add_interviews(
    design, interviews,
    catch         = catch_count,
    harvest       = harvest_count,
    effort        = effort,
    trip_status   = trip_status,
    n_counted     = n_counted,
    n_interviewed = n_interviewed
  ))
}

reference_outputs <- function() {
  utils::read.csv(file.path(calamus_dir(), "reference-outputs.csv"), stringsAsFactors = FALSE)
}

# --- the composition ---

test_that("a fetched Calamus design reproduces the reference effort total (GH #130)", {
  design <- build_calamus_design(calamus_conn())
  ref    <- reference_outputs()
  want   <- ref[ref$estimand == "effort_total", ]

  got <- suppressWarnings(tidycreel::estimate_effort(design))

  expect_equal(got$estimates$estimate, want$estimate, tolerance = 1e-6)
  # The SE too: a dropped variance component leaves the point estimate intact,
  # which is how every uncertainty defect here has escaped notice.
  expect_equal(got$estimates$se, want$se, tolerance = 1e-6)
})

test_that("a fetched Calamus design reproduces the reference catch total", {
  design <- build_calamus_design(calamus_conn())
  ref    <- reference_outputs()
  want   <- ref[ref$estimand == "catch_total", ]

  got <- suppressWarnings(tidycreel::estimate_total_catch(design))

  expect_equal(got$estimates$estimate, want$estimate, tolerance = 1e-6)
  # The SE too. This row's SE was re-baselined at v3.0.0 and the reason is
  # recorded in the fixture README; asserting only the point estimate is what
  # let the stale value sit unnoticed from v1.7.0 to v4.0.0 (GH #178).
  expect_equal(got$estimates$se, want$se, tolerance = 1e-6)
})

test_that("the catch total drops incomplete trips, moving the SE but not the estimate", {
  # Why the reference catch SE moved between v1.7.0 and v3.0.0, asserted rather
  # than described: v3.0.0 (58e0424b, PR #114) routed the bus-route catch total
  # through br_complete_trips_only(), which the harvest total had always applied.
  #
  # The two incomplete rows on this fixture (interview_uid 5) both carry
  # catch_count = 0, so the filter cannot move the Horvitz-Thompson sum -- only
  # the interview count behind the variance, 24 -> 22. That is why the earlier
  # reading of this divergence was wrong: "the point estimate is invariant to the
  # trip filter" is what zero-catch rows guarantee, not evidence the filter is
  # unrelated to the SE.
  design <- build_calamus_design(calamus_conn())
  ref    <- reference_outputs()
  want   <- ref[ref$estimand == "catch_total", ]

  got <- suppressWarnings(tidycreel::estimate_total_catch(design))
  expect_equal(got$estimates$n, 22)

  # Relabelling the two incomplete rows defeats the filter and must recover the
  # pre-v3.0.0 SE exactly -- the point estimate staying put while the SE moves is
  # the whole finding.
  unfiltered <- build_calamus_design(calamus_conn())
  unfiltered$interviews[[unfiltered$trip_status_col]] <- "complete"
  got_all <- suppressWarnings(tidycreel::estimate_total_catch(unfiltered))

  expect_equal(got_all$estimates$n, 24)
  expect_equal(got_all$estimates$estimate, got$estimates$estimate, tolerance = 1e-9)
  expect_equal(got_all$estimates$se, 55.7238941653612, tolerance = 1e-6)
  expect_false(isTRUE(all.equal(got_all$estimates$se, want$se, tolerance = 1e-6)))
})

test_that("a fetched Calamus design reproduces the reference harvest total", {
  # estimate_total_harvest(), not estimate_harvest_rate(): the latter returns
  # HPUE (0.4226 on this fixture), and the reference records the Horvitz-Thompson
  # total. The shipped validation script called the rate function and argued in a
  # comment against the total -- it had aborted earlier for years, so nothing
  # caught the mismatch (GH #130).
  design <- build_calamus_design(calamus_conn())
  ref    <- reference_outputs()
  want   <- ref[ref$estimand == "harvest_total", ]

  got <- suppressWarnings(tidycreel::estimate_total_harvest(design))

  expect_equal(got$estimates$estimate, want$estimate, tolerance = 1e-6)
  expect_equal(got$estimates$se, want$se, tolerance = 1e-6)
})

test_that("the fetched interviews carry every column the design consumes", {
  # The #126/#171 failure mode stated directly: a column that exists in the
  # source, is dropped by the fetch, and is only missed several stages later.
  interviews <- suppressMessages(fetch_interviews(calamus_conn()))

  expect_true(all(
    c("interview_uid", "date", "site", "circuit", "effort", "catch_count",
      "trip_status", "n_counted", "n_interviewed") %in% names(interviews)
  ))
})

test_that("the composed estimate moves when a fetched column is withheld", {
  # A composition test that passes whatever the fetch delivers proves nothing.
  # Dropping the enumeration columns the bus-route weights are built from must
  # change the answer or abort -- either way, not agree silently.
  design <- build_calamus_design(calamus_conn())
  baseline <- suppressWarnings(tidycreel::estimate_effort(design))$estimates$estimate

  conn <- calamus_conn()
  interviews <- suppressMessages(fetch_interviews(conn))
  interviews <- attach_harvest(interviews, suppressMessages(fetch_catch(conn)))
  counts <- suppressMessages(suppressWarnings(fetch_counts(conn)))
  counts <- merge(counts, calamus_calendar()[c("date", "day_type")], by = "date", all.x = TRUE)

  d2 <- tidycreel::creel_design(
    calendar = calamus_calendar(), date = date, strata = day_type,
    survey_type = "bus_route", sampling_frame = calamus_frame(),
    site = site, circuit = circuit, p_site = p_site, p_period = p_period
  )
  d2 <- suppressWarnings(tidycreel::add_counts(d2, counts, count_col = bank_anglers))

  withheld <- tryCatch(
    {
      d2 <- suppressWarnings(tidycreel::add_interviews(
        d2, interviews,
        catch = catch_count, harvest = harvest_count,
        effort = effort, trip_status = trip_status
      ))
      suppressWarnings(tidycreel::estimate_effort(d2))$estimates$estimate
    },
    error = function(e) NA_real_
  )

  # Either it refused, or it produced a different number. Agreement would mean
  # the enumeration columns never reached the calculation at all.
  expect_true(is.na(withheld) || !isTRUE(all.equal(withheld, baseline)))
})

# --- the boat seam, on deliberately synthetic counts ---

# calamus-2016 is a bank-only fishery: angler_boats and non_ang_boats both sum to
# zero, so the boat-to-angler reconstruction path cannot be reached by any test
# built on it. These counts are fabricated for that purpose alone
# (inst/extdata/synthetic-boat-counts/README.md says so at the fixture). Nothing
# here compares an estimate to a reference value -- there is none, and a total
# computed from invented counts is arithmetic rather than validation. What is
# asserted is the seam: that boat counts survive the fetch and change the answer.

synthetic_boat_counts <- function() {
  p <- system.file("extdata", "synthetic-boat-counts", "counts.csv", package = "tidycreel.connect")
  if (!nzchar(p)) {
    p <- testthat::test_path("..", "..", "inst", "extdata", "synthetic-boat-counts", "counts.csv")
  }
  if (!file.exists(p)) testthat::skip("synthetic boat-counts fixture not found")
  p
}

test_that("boat counts survive the fetch (GH #130)", {
  conn   <- calamus_conn(counts = synthetic_boat_counts())
  counts <- suppressMessages(suppressWarnings(fetch_counts(conn)))

  expect_true(all(c("bank_anglers", "angler_boats", "non_ang_boats") %in% names(counts)))
  # Non-zero and row-for-row the source's own values: the bank-only fixture
  # cannot tell a carried boat column from a zeroed one.
  expect_equal(counts$angler_boats, c(4, 3, 2, 5, 3, 6, 4))
  expect_equal(counts$bank_anglers, c(10, 8, 12, 6, 9, 14, 11))
  expect_gt(sum(counts$angler_boats), 0)
})

test_that("boat anglers reach the estimate and move it (GH #130)", {
  # On an INSTANTANEOUS design, where the count column is the effort basis.
  # Not bus-route: there effort is the Horvitz-Thompson estimator over the
  # interview-side enumeration, so the counts table never enters
  # estimate_effort() and bank-only and reconstructed counts give the identical
  # 626.25 -- a seam test built on it would pass no matter what the fetch did.
  conn   <- calamus_conn(counts = synthetic_boat_counts())
  counts <- suppressMessages(suppressWarnings(fetch_counts(conn)))
  counts <- merge(counts, calamus_calendar()[c("date", "day_type")], by = "date", all.x = TRUE)

  reconstructed <- tidycreel::derive_angler_count(
    counts,
    bank       = bank_anglers,
    boat_count = angler_boats,
    party_size = 2.5
  )

  expect_true("angler_count" %in% names(reconstructed))
  # Day one: 10 bank anglers + 4 boats x 2.5 anglers per boat.
  expect_equal(reconstructed$angler_count[1], 10 + 4 * 2.5)
  expect_gt(sum(reconstructed$angler_count), sum(counts$bank_anglers))

  # Reduced to date, stratum and the one count column under test, so
  # add_counts() has a single numeric candidate and no selector is needed.
  effort_from <- function(cnt, col) {
    slim <- data.frame(
      date     = cnt$date,
      day_type = cnt$day_type,
      anglers  = cnt[[col]],
      stringsAsFactors = FALSE
    )
    design <- tidycreel::creel_design(
      calendar = calamus_calendar(), date = date, strata = day_type,
      survey_type = "instantaneous"
    )
    design <- suppressWarnings(tidycreel::add_counts(design, slim, count_col = anglers))
    suppressWarnings(tidycreel::estimate_effort(design))$estimates$estimate
  }

  bank_only  <- effort_from(counts, "bank_anglers")
  with_boats <- effort_from(reconstructed, "angler_count")

  # 27 boats x 2.5 anglers = 67.5 anglers the bank-only path never counted.
  expect_gt(with_boats, bank_only)
  expect_equal(with_boats - bank_only, sum(counts$angler_boats) * 2.5, tolerance = 1e-6)
})

# nolint end
