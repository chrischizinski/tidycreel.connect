# design_calendar() (#4, part C): the calendar tidycreel::creel_design() takes,
# built from fetch_design()'s tables and the counts. The design says what
# could be drawn; the counts say which day was worked and which shift.

# A season from Saturday 28 June to Sunday 6 July 2025: two months, both day
# types. Two 5 h shifts a day, drawn with p = 0.6 and 0.4.
cal_design <- function(periods = cal_periods(), special = NULL, general = list()) {
  g <- data.frame(
    creel_uid = "creel-a",
    season_start = as.Date("2025-06-28"),
    season_end = as.Date("2025-07-06")
  )
  for (nm in names(general)) g[[nm]] <- general[[nm]]
  list(general = g, periods = periods, sections = NULL, special_dates = special)
}

cal_periods <- function(start = c("06:00", "13:00"), end = c("11:00", "18:00"),
                        p = c(0.6, 0.4)) {
  start_min <- as.integer(substr(start, 1, 2)) * 60L + as.integer(substr(start, 4, 5))
  end_min <- as.integer(substr(end, 1, 2)) * 60L + as.integer(substr(end, 4, 5))
  crosses <- end_min <= start_min
  one <- data.frame(
    creel_uid = "creel-a",
    period_id = as.character(seq_along(start)),
    start_time = start,
    end_time = end,
    length_hours = (end_min - start_min + ifelse(crosses, 1440, 0)) / 60,
    crosses_midnight = crosses,
    p_period = p
  )
  rbind(cbind(month = 6L, one), cbind(month = 7L, one))
}

# Two counts on each worked day; `period` is the shift drawn.
cal_counts <- function(date = as.Date(c("2025-06-28", "2025-06-30", "2025-07-02", "2025-07-05")),
                       period = c("1", "2", "1", "2")) {
  data.frame(
    creel_uid = "creel-a",
    date = rep(date, each = 2),
    count_time = rep(c("a", "b"), length(date)),
    bank_anglers = rep(c(10, 14, 6, 9, 22, 30, 18, 25), length.out = 2 * length(date)),
    period = rep(period, each = 2)
  )
}

test_that("every season day is in the calendar; only worked days carry a shift", {
  cal <- design_calendar(cal_design(), cal_counts())
  # Unsampled days are population days the totals expand to: none may be lost.
  expect_identical(cal$date, seq(as.Date("2025-06-28"), as.Date("2025-07-06"), by = "day"))
  worked <- cal$date %in% as.Date(c("2025-06-28", "2025-06-30", "2025-07-02", "2025-07-05"))
  expect_true(all(is.na(cal$p_period[!worked])))
  expect_true(all(is.na(cal$period_id[!worked])))
  expect_identical(cal$period_id[worked], c("1", "2", "1", "2"))
  expect_identical(cal$p_period[worked], c(0.6, 0.4, 0.6, 0.4))
  expect_identical(cal$shift_start[worked], c("06:00", "13:00", "06:00", "13:00"))
  expect_false("day_start" %in% names(cal))
})

test_that("ordinary days are stratified by month x day type", {
  cal <- design_calendar(cal_design(), cal_counts())
  expect_identical(cal$month, c(6L, 6L, 6L, rep(7L, 6)))
  # 28-29 June and 5-6 July are weekends.
  expect_identical(
    cal$stratum,
    c("06_weekend", "06_weekend", "06_weekday", rep("07_weekday", 4), "07_weekend", "07_weekend")
  )
})

test_that("the length is the real one; tidycreel divides by p itself", {
  cal <- design_calendar(cal_design(), cal_counts())
  # Not 5 / 0.6 or 5 / 0.4: a length already divided by p is p applied twice.
  expect_identical(unique(cal$shift_hours[!is.na(cal$shift_hours)]), 5)

  cn <- cal_counts()
  i <- match(cn$date, cal$date)
  cn$stratum <- cal$stratum[i]
  add <- function(hours) {
    cn$hours <- hours
    d <- suppressMessages(tidycreel::creel_design(cal, date = date, strata = stratum))
    suppressWarnings(suppressMessages(tidycreel::add_counts(
      d, cn,
      count_col = bank_anglers, count_time_col = count_time, period_length_col = hours
    )))
  }
  expect_no_error(add(cal$shift_hours[i]))
  expect_error(add(cal$shift_hours[i] / cal$p_period[i]), class = "creel_error_p_period_applied_twice")
})

test_that("counts in two shifts on one day are refused, with the day named", {
  cn <- cal_counts()
  cn$period[2] <- "2"
  expect_error(design_calendar(cal_design(), cn), class = "creel_error_calendar_two_shifts")
  expect_error(design_calendar(cal_design(), cn), "2025-06-28")
})

test_that("a count with no shift, an unknown shift, or outside the season is refused", {
  cn <- cal_counts()
  cn$period[3:4] <- NA
  expect_error(design_calendar(cal_design(), cn), "name no shift")

  cn <- cal_counts(period = c("1", "3", "1", "2"))
  expect_error(design_calendar(cal_design(), cn), "2025-06-30: period 3")

  cn <- cal_counts(date = as.Date(c("2025-06-27", "2025-06-30", "2025-07-02", "2025-07-05")))
  expect_error(design_calendar(cal_design(), cn), "outside the season")

  # A month the design does not cover is a shift it does not have.
  expect_error(
    design_calendar(cal_design(periods = cal_periods()[1:2, ]), cal_counts()),
    "does not have"
  )
})

test_that("the drawn shift is read from period_col", {
  cn <- cal_counts()
  names(cn)[names(cn) == "period"] <- "shift"
  expect_error(design_calendar(cal_design(), cn), "no .*period.* column")
  expect_identical(
    design_calendar(cal_design(), cn, period_col = "shift"),
    design_calendar(cal_design(), cal_counts())
  )
})

test_that("special dates follow the design's rule or the argument", {
  special <- data.frame(
    creel_uid = "creel-a",
    date = as.Date(c("2025-07-03", "2025-07-04")),
    group = "july4"
  )
  hol <- as.Date(c("2025-07-03", "2025-07-04"))

  as_stratum <- design_calendar(
    cal_design(special = special, general = list(special_as_stratum = TRUE, special_as_weekend = FALSE)),
    cal_counts()
  )
  expect_identical(as_stratum$stratum[as_stratum$date %in% hol], c("special_july4", "special_july4"))
  expect_identical(unique(as_stratum$day_type[as_stratum$date %in% hol]), "special")

  as_weekend <- design_calendar(
    cal_design(special = special, general = list(special_as_stratum = FALSE, special_as_weekend = TRUE)),
    cal_counts()
  )
  expect_identical(as_weekend$stratum[as_weekend$date %in% hol], c("07_weekend", "07_weekend"))

  ignored <- design_calendar(
    cal_design(special = special, general = list(special_as_stratum = FALSE, special_as_weekend = FALSE)),
    cal_counts()
  )
  expect_identical(ignored$stratum[ignored$date %in% hol], c("07_weekday", "07_weekday"))

  # The argument overrides the design.
  expect_identical(
    design_calendar(
      cal_design(special = special, general = list(special_as_stratum = FALSE, special_as_weekend = TRUE)),
      cal_counts(), special_dates = "ignore"
    ),
    ignored
  )

  # A design that does not say is refused rather than guessed.
  expect_error(design_calendar(cal_design(special = special), cal_counts()), "does not say")
  expect_error(
    design_calendar(
      cal_design(special = special, general = list(special_as_stratum = TRUE, special_as_weekend = TRUE)),
      cal_counts()
    ),
    "both"
  )
  outside <- special
  outside$date[1] <- as.Date("2025-08-01")
  expect_error(design_calendar(cal_design(special = outside), cal_counts(), special_dates = "weekend"), "outside")
  no_group <- special
  no_group$group <- NA_character_
  expect_error(design_calendar(cal_design(special = no_group), cal_counts(), special_dates = "stratum"), "group")
})

# Night shifts 19:30-00:30 on 30 June and 5 July: each has a count after
# midnight, dated the next day, as it was made.
night_periods <- function() cal_periods(start = c("06:00", "19:30"), end = c("11:00", "00:30"))
night_counts <- function() {
  cn <- cal_counts()
  day <- cn$period == "1"
  cn$count_time <- ifelse(day, c("07:00", "10:00"), c("20:00", "00:15"))
  late <- cn$count_time == "00:15"
  cn$date[late] <- cn$date[late] + 1
  cn
}

test_that("a shift that crosses midnight makes a night calendar", {
  withr::local_options(tidycreel.tz = "America/Chicago")
  periods <- night_periods()
  cal <- design_calendar(cal_design(periods = periods), night_counts())
  # The 19:30-00:30 shift is 5 h, not the -19 h of end - start.
  expect_identical(cal$shift_hours[cal$date == as.Date("2025-06-30")], 5)
  # Survey days start at the earliest shift start, so both shifts fit in one.
  expect_identical(unique(cal$day_start), "06:00")
  expect_identical(
    design_calendar(cal_design(periods = periods), night_counts(), day_start = "05:00")$day_start[1],
    "05:00"
  )
  # 08:00 splits the 06:00-11:00 shift across two survey days.
  expect_error(
    design_calendar(cal_design(periods = periods), night_counts(), day_start = "08:00"),
    "does not fit"
  )
  # A day design carries no day_start, whatever the argument.
  expect_false("day_start" %in% names(design_calendar(cal_design(), cal_counts(), day_start = "08:00")))
})

test_that("a count after midnight works the night before, as tidycreel reads it", {
  withr::local_options(tidycreel.tz = "America/Chicago")
  cn <- night_counts()
  cal <- design_calendar(cal_design(periods = night_periods()), cn)
  # Read by date alone, the 00:15 count of 30 June's night would make 1 July
  # a worked day -- one tidycreel then finds no count for.
  worked <- cal$date[!is.na(cal$period_id)]
  expect_equal(worked, as.Date(c("2025-06-28", "2025-06-30", "2025-07-02", "2025-07-05")))

  # The calendar and the counts agree for tidycreel: the night is expanded
  # with the real 5 h, and 5 h / p is refused as p applied twice.
  i <- match(cn$date - as.integer(cn$count_time == "00:15"), cal$date)
  cn$stratum <- cal$stratum[i]
  add <- function(hours) {
    cn$hours <- hours
    d <- suppressMessages(tidycreel::creel_design(
      cal, date = date, strata = stratum, tz = "America/Chicago"
    ))
    suppressWarnings(suppressMessages(tidycreel::add_counts(
      d, cn,
      count_col = bank_anglers, count_time_col = count_time, period_length_col = hours
    )))
  }
  expect_no_error(add(cal$shift_hours[i]))
  expect_error(add(cal$shift_hours[i] / cal$p_period[i]), class = "creel_error_p_period_applied_twice")

  # Without clock times a count's night is unknown: refused, not guessed.
  expect_error(design_calendar(cal_design(periods = night_periods()), cal_counts()), "clock time")
})

test_that("a design with several creels needs creel_uid", {
  d <- cal_design()
  other <- d
  other$general$creel_uid <- "creel-b"
  other$general$season_start <- as.Date("2025-07-01")
  other$periods$creel_uid <- "creel-b"
  both <- list(
    general = rbind(d$general, other$general),
    periods = rbind(d$periods, other$periods),
    sections = NULL, special_dates = NULL
  )
  cn <- rbind(cal_counts(), transform(cal_counts(), creel_uid = "creel-b"))
  expect_error(design_calendar(both, cn), "creel_uid")
  # Each creel's own season, and only its own counts.
  expect_identical(design_calendar(both, cn, creel_uid = "creel-a"), design_calendar(d, cal_counts()))
  expect_error(design_calendar(both, cn, creel_uid = "creel-b"), "outside the season")
  expect_error(design_calendar(both, cn, creel_uid = "creel-c"), "one of")
})

test_that("a night's length is its elapsed time across a daylight-saving change", {
  # tidycreel takes a calendar's shift_hours as given: the month's clock
  # length (8 h) on the night clocks fall back would understate its effort.
  d <- cal_design(periods = cal_periods(start = "19:00", end = "03:00", p = 1))
  d$general$season_start <- as.Date("2025-10-31")
  d$general$season_end <- as.Date("2025-11-02")
  d$periods$month <- rep(c(10L, 11L), each = 1)
  cn <- function(date) {
    data.frame(date = date + c(0, 1), count_time = c("20:00", "01:00"), bank_anglers = 1, period = "1")
  }
  fall <- design_calendar(d, cn(as.Date("2025-11-01")), tz = "America/Chicago")
  expect_identical(fall$shift_hours[fall$date == as.Date("2025-11-01")], 9)
  # Elsewhere the night is its clock length.
  plain <- design_calendar(d, cn(as.Date("2025-10-31")), tz = "America/Chicago")
  expect_identical(plain$shift_hours[plain$date == as.Date("2025-10-31")], 8)
  # In a zone without the change it is the clock length too.
  expect_identical(
    design_calendar(d, cn(as.Date("2025-11-01")), tz = "UTC")$shift_hours[2],
    8
  )

  # A night design without a zone is refused, not read in the computer's.
  withr::local_options(tidycreel.tz = NULL)
  expect_error(design_calendar(d, cn(as.Date("2025-11-01"))), "time zone")

  # A shift ending in the repeated hour has no single length.
  d$periods$end_time <- "01:30"
  d$periods$length_hours <- 6.5
  expect_error(
    design_calendar(d, cn(as.Date("2025-11-01")), tz = "America/Chicago"),
    "skipped or repeated"
  )
})

test_that("conflicting definitions in the design are refused, not chosen by row order", {
  # Two rows for June period 1 with p 0.6 and 0.25: which one matched first
  # would change the day's expansion more than twofold.
  p <- cal_periods()
  extra <- p[1, ]
  extra$p_period <- 0.25
  expect_error(design_calendar(cal_design(periods = rbind(p, extra)), cal_counts()), "month 6, period 1")
  # An identical repeat is the same definition.
  expect_identical(
    design_calendar(cal_design(periods = rbind(p, p[1, ])), cal_counts()),
    design_calendar(cal_design(), cal_counts())
  )

  special <- data.frame(
    creel_uid = "creel-a", date = as.Date(c("2025-07-04", "2025-07-04")), group = c("x", "y")
  )
  expect_error(
    design_calendar(cal_design(special = special), cal_counts(), special_dates = "stratum"),
    "more than one group"
  )
})
