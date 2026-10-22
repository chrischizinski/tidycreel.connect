# fetch_design() (#4, part B): the creel's own design tables, read through the
# profile and renamed to canonical columns. Field names below are invented.

design_endpoints <- function() {
  list(
    design_general       = "v2/design/general",
    design_periods       = "v2/design/periods",
    design_sections      = "v2/design/sections",
    design_special_dates = "v2/design/special"
  )
}

design_field_map <- function() {
  list(
    design_general = list(
      season_start       = "StartDate",
      season_end         = "EndDate",
      special_as_stratum = "HighUse",
      special_as_weekend = "Holidays"
    ),
    design_periods = list(
      month               = "Month",
      period_id           = "Period",
      start_time          = "Start",
      end_time            = "End",
      stored_length_hours = "Hours",
      p_period            = "Prob"
    ),
    design_sections      = list(section = "Section"),
    design_special_dates = list(date = "Day", group = "Group")
  )
}

design_conn <- function(uids = "creel-a", endpoints = design_endpoints()) {
  tidycreel.connect::creel_connect_api(
    base_url      = "http://test.example.com/api/",
    creel_uids    = uids,
    schema        = tidycreel::creel_schema(survey_type = "instantaneous"),
    uid_param     = "survey_id",
    endpoints     = endpoints,
    api_field_map = design_field_map()[names(endpoints)]
  )
}

# Bodies keyed by the endpoint path's last segment.
mock_design <- function(bodies, env = parent.frame()) {
  httr2::local_mocked_responses(function(req) {
    key <- basename(httr2::url_parse(req$url)$path)
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body    = charToRaw(bodies[[key]])
    )
  }, env = env)
}

day_shift_bodies <- function() {
  list(
    general  = paste0(
      '[{"StartDate":"2025-04-01T00:00:00","EndDate":"2025-10-31T00:00:00",',
      '"HighUse":true,"Holidays":false}]'
    ),
    periods  = paste0(
      '[{"Month":4,"Period":1,"Start":"06:00","End":"13:30","Hours":7.5,"Prob":0.5},',
      '{"Month":4,"Period":2,"Start":"13:30:00","End":"21:00:00","Hours":7.5,"Prob":0.5}]'
    ),
    sections = '[{"Section":"North"},{"Section":"South"}]',
    special  = '[{"Day":"2025-05-24","Group":"Memorial"}]'
  )
}

test_that("all four tables arrive with canonical names and types", {
  mock_design(day_shift_bodies())
  d <- suppressMessages(fetch_design(design_conn()))
  expect_named(d, c("general", "periods", "sections", "special_dates"))

  expect_s3_class(d$general$season_start, "Date")
  expect_identical(d$general$season_end, as.Date("2025-10-31"))
  expect_identical(d$general$special_as_stratum, TRUE)
  expect_identical(d$general$special_as_weekend, FALSE)

  p <- d$periods
  expect_type(p$month, "integer")
  expect_type(p$period_id, "character")
  # Clock times normalised whatever shape they arrived in.
  expect_identical(p$start_time, c("06:00", "13:30"))
  expect_identical(p$end_time, c("13:30", "21:00"))
  expect_equal(p$length_hours, c(7.5, 7.5))
  expect_identical(p$crosses_midnight, c(FALSE, FALSE))
  expect_equal(p$p_period, c(0.5, 0.5))

  expect_identical(d$sections$section, c("North", "South"))
  expect_identical(d$special_dates$date, as.Date("2025-05-24"))
  # Every table says which creel it came from (#2).
  expect_true(all(vapply(d, function(t) all(t$creel_uid == "creel-a"), logical(1))))
})

test_that("a night shift's length comes from the window, and a wrong stored one is reported", {
  # The field case: 19:30-00:30 stored as end - start on a clock that wraps,
  # -19 h, which reached published reports. 00:30-06:00 is stored right.
  bodies <- day_shift_bodies()
  bodies$periods <- paste0(
    '[{"Month":4,"Period":1,"Start":"1900-01-01T19:30:00","End":"1900-01-01T00:30:00",',
    '"Hours":-19,"Prob":0.5},',
    '{"Month":4,"Period":2,"Start":"00:30","End":"06:00","Hours":5.5,"Prob":0.5}]'
  )
  mock_design(bodies)
  expect_warning(
    d <- suppressMessages(fetch_design(design_conn())),
    "stored -19 h, window 5 h",
    class = "creel_warning_design_length_disagrees"
  )
  expect_equal(d$periods$length_hours, c(5, 5.5))
  expect_identical(d$periods$crosses_midnight, c(TRUE, FALSE))
  # Both values are kept; nothing is silently preferred.
  expect_equal(d$periods$stored_length_hours, c(-19, 5.5))
})

test_that("agreeing stored lengths raise nothing", {
  mock_design(day_shift_bodies())
  expect_no_warning(suppressMessages(fetch_design(design_conn())))
})

test_that("a probability outside (0, 1] is refused", {
  bodies <- day_shift_bodies()
  bodies$periods <- sub('"Prob":0.5}]', '"Prob":2}]', bodies$periods, fixed = TRUE)
  mock_design(bodies)
  expect_error(suppressMessages(fetch_design(design_conn())), "outside \\(0, 1\\]")
})

test_that("a period with no readable clock time is refused", {
  bodies <- day_shift_bodies()
  bodies$periods <- sub('"Start":"06:00"', '"Start":"morning"', bodies$periods, fixed = TRUE)
  mock_design(bodies)
  expect_error(suppressMessages(fetch_design(design_conn())), "not a clock time")
})

test_that("a missing season or period table is refused, optional ones are NULL", {
  # No sections or special-dates endpoint: those tables are NULL, not errors.
  mock_design(day_shift_bodies())
  d <- suppressMessages(fetch_design(design_conn(
    endpoints = design_endpoints()[c("design_general", "design_periods")]
  )))
  expect_null(d$sections)
  expect_null(d$special_dates)

  # A season with no rows cannot be built into a calendar.
  bodies <- day_shift_bodies()
  bodies$general <- "[]"
  mock_design(bodies)
  expect_error(suppressMessages(fetch_design(design_conn())), "returned no rows")
})

test_that("a season with no special dates returns an empty table", {
  bodies <- day_shift_bodies()
  bodies$special <- "[]"
  mock_design(bodies)
  d <- suppressMessages(fetch_design(design_conn()))
  expect_identical(nrow(d$special_dates), 0L)
  expect_s3_class(d$special_dates$date, "Date")
})

test_that("each creel's design is labelled on a multi-creel connection", {
  mock_design(day_shift_bodies())
  d <- suppressMessages(fetch_design(design_conn(c("creel-a", "creel-b"))))
  expect_identical(d$general$creel_uid, c("creel-a", "creel-b"))
  expect_identical(nrow(d$periods), 4L)
})

test_that("a non-API connection is refused", {
  skip_if_not_installed("withr")
  conn <- creel_connect(make_test_csv(), make_test_schema())
  expect_error(fetch_design(conn), "API connection")
})

test_that("an impossible or missing clock time is refused, not read in part", {
  # Matched anywhere inside the value, 25:10:00 read as 10:00 and gave the
  # shift a wrong length with nothing said.
  clock <- tidycreel.connect:::.clock_minutes
  expect_error(clock("25:10:00", "start_time"), "not a clock time")
  expect_error(clock(c("06:00", NA), "start_time"), "not a clock time")
  expect_identical(
    clock(c("6:05", "19:30:00", "1900-01-01T00:30:00", "2025-04-01 13:30:00Z"), "x"),
    c(365L, 1170L, 30L, 810L)
  )
})

test_that("a missing probability or season date is refused", {
  bodies <- day_shift_bodies()
  bodies$periods <- sub('"Prob":0.5}]', '"Prob":null}]', bodies$periods, fixed = TRUE)
  mock_design(bodies)
  expect_error(suppressMessages(fetch_design(design_conn())), "missing or outside")

  bodies <- day_shift_bodies()
  bodies$general <- sub('"2025-10-31T00:00:00"', 'null', bodies$general, fixed = TRUE)
  mock_design(bodies)
  expect_error(
    suppressWarnings(suppressMessages(fetch_design(design_conn()))),
    "season start or end"
  )
})

test_that("every creel on the connection needs its own season", {
  # Empty blocks drop out when creels are bound, so creel-b's missing season
  # vanished while its periods stayed.
  httr2::local_mocked_responses(function(req) {
    q <- httr2::url_parse(req$url)
    body <- day_shift_bodies()[[basename(q$path)]]
    if (basename(q$path) == "general" && q$query$survey_id == "creel-b") body <- "[]"
    httr2::response(200, headers = "Content-Type: application/json", body = charToRaw(body))
  })
  expect_error(
    suppressMessages(fetch_design(design_conn(c("creel-a", "creel-b")))),
    "no rows for creel \"creel-b\""
  )
})

test_that("an empty special-dates table keeps a mapped group column", {
  bodies <- day_shift_bodies()
  bodies$special <- "[]"
  mock_design(bodies)
  d <- suppressMessages(fetch_design(design_conn()))
  expect_true("group" %in% names(d$special_dates))
})

test_that("a month or a time that would be truncated is refused", {
  # 4.9 read as April, and 06:00:10-06:00:50 as a 24-hour shift, with nothing
  # said when no stored length was mapped.
  bodies <- day_shift_bodies()
  bodies$periods <- sub('"Month":4,"Period":1', '"Month":4.9,"Period":1', bodies$periods, fixed = TRUE)
  mock_design(bodies)
  expect_error(suppressMessages(fetch_design(design_conn())), "whole month 1-12")

  clock <- tidycreel.connect:::.clock_minutes
  expect_error(clock("06:00:10", "start_time"), "not a clock time")
  expect_identical(clock(c("06:00:00", "06:00:00.000"), "start_time"), c(360L, 360L))
})
