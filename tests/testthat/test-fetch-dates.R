# Date parsing must not depend on row order (#13). as.Date(tryFormats =) takes
# its format from the first non-NA value and errors when that value fits none,
# so one bad date in row 1 aborted the fetch with an unclassed base-R error,
# while the same value in row 2 became NA with the classed warning. A caller
# could handle the second by class and not the first.

dates_csv_conn <- function(paths, dates) {
  iv <- utils::read.csv(paths$interviews)
  iv <- iv[rep(1L, length(dates)), ]
  iv$interview_uid <- seq_along(dates)
  iv$date <- dates
  utils::write.csv(iv, paths$interviews, row.names = FALSE)
  creel_connect(paths, make_test_schema())
}

test_that("an unreadable first date is NA with the classed warning, not an abort", {
  skip_if_not_installed("withr")
  conn <- dates_csv_conn(make_test_csv(), c("not a date", "2024-06-02"))
  result <- NULL
  expect_warning(
    result <- suppressMessages(fetch_interviews(conn)),
    "Could not parse 1 date value",
    class = "creel_warning_dates_coerced_na"
  )
  expect_true(is.na(result$date[[1]]))
  expect_equal(result$date[[2]], as.Date("2024-06-02"))
})

test_that("the format comes from the first readable value", {
  # Row 1 fits no format; row 2 is month/day/year. Taking the format from row
  # 2 reads the rest of the column, where giving up on row 1 read none of it.
  out <- suppressWarnings(tidycreel.connect:::.coerce_date(
    c("garbage", "06/02/2024", "06/03/2024"), "date"
  ))
  expect_equal(out, as.Date(c(NA, "2024-06-02", "2024-06-03")))
})

test_that("a readable first value gives exactly what as.Date() gave", {
  # The fix must not change any column that already parsed: one format per
  # column, chosen from row 1, with values in another format becoming NA.
  cases <- list(
    c("2024-06-01", "2024-06-02"),
    c("06/01/2024", "06/02/2024"),
    c("2024-06-01", "06/02/2024"),
    c(NA, "2024-06-01", "bad")
  )
  for (x in cases) {
    expect_equal(
      suppressWarnings(tidycreel.connect:::.coerce_date(x, "date")),
      suppressWarnings(as.Date(x, tryFormats = c("%Y-%m-%d", "%m/%d/%Y"))),
      info = paste(x, collapse = ", ")
    )
  }
})

test_that("a column no format reads is all NA, and the warning counts every value", {
  expect_warning(
    out <- tidycreel.connect:::.coerce_date(c("x", "y", NA), "date"),
    "Could not parse 2 date values",
    class = "creel_warning_dates_coerced_na"
  )
  expect_true(all(is.na(out)))
  expect_s3_class(out, "Date")
})

test_that("an unreadable API date warns instead of becoming NA silently", {
  # The API parser had the same row-1 abort, and below row 1 it set NA with no
  # warning at all, where the CSV path warned.
  expect_warning(
    out <- tidycreel.connect:::.parse_api_date(
      c("2016-03-28T08:00:00Z", "not a date")
    ),
    class = "creel_warning_dates_coerced_na"
  )
  expect_equal(out, as.Date(c("2016-03-28", NA)))
  expect_warning(
    out <- tidycreel.connect:::.parse_api_date(c("not a date", "2016-03-28")),
    class = "creel_warning_dates_coerced_na"
  )
  expect_equal(out, as.Date(c(NA, "2016-03-28")))
})
