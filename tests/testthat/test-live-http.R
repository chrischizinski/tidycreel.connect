# The transport half of GH #330 item 2: a real server, over a real socket.
#
# See helper-live-http.R for why. In short: every other API test here mocks
# BELOW `req_perform()`, so none of them has ever performed a request. These do.

# --- the request itself — HTTP-01..04 ----------------------------------------

test_that("a fetch performs a real request and returns real rows (HTTP-01)", {
  skip_if_no_webfakes()
  srv <- webfakes::new_app_process(live_http_app())
  on.exit(srv$stop(), add = TRUE)

  conn <- live_http_conn(srv$url("/"), pagination = list(style = "link"))
  got <- suppressMessages(fetch_interviews(conn))

  # 24 interviews across 3 pages of 10, so this cannot pass without the
  # pagination loop performing three separate requests.
  expect_equal(nrow(got), 24L)
  expect_true(all(c("interview_uid", "date", "trip_status", "effort") %in% names(got)))
  # The rename did real work: no JSON key survives into the result.
  expect_false(any(c("InterviewID", "SurveyDate", "HoursFished") %in% names(got)))
})

test_that("the bearer token is actually sent (HTTP-02)", {
  # The server 401s without it, so this asserts the auth header reaches the
  # wire rather than merely being attached to a request object.
  skip_if_no_webfakes()
  srv <- webfakes::new_app_process(live_http_app())
  on.exit(srv$stop(), add = TRUE)

  expect_error(
    suppressMessages(fetch_interviews(live_http_conn(
      srv$url("/"), pagination = list(style = "link"), token = "wrong"
    ))),
    "API request failed \\[401\\]"
  )
  ok <- live_http_conn(srv$url("/"), pagination = list(style = "link"))
  expect_equal(nrow(suppressMessages(fetch_interviews(ok))), 24L)
})

test_that("JSON types survive the wire (HTTP-03)", {
  # simplifyVector turns a JSON array of flat objects into a data.frame, and
  # what each column becomes is decided by the payload, not by us. A date
  # arrives as a string and must be parsed; an effort must arrive numeric or
  # every rate downstream is computed on text.
  skip_if_no_webfakes()
  srv <- webfakes::new_app_process(live_http_app())
  on.exit(srv$stop(), add = TRUE)

  conn <- live_http_conn(srv$url("/"), pagination = list(style = "link"))
  got <- suppressMessages(fetch_interviews(conn))
  expect_s3_class(got$date, "Date")
  expect_type(got$effort, "double")
  expect_type(got$interview_uid, "character")
})

test_that("an HTTP error surfaces with its status (HTTP-04)", {
  skip_if_no_webfakes()
  app <- webfakes::new_app()
  app$get("/v2/interviews", function(req, res) {
    res$set_status(503L)$send_json(list(error = "down"), auto_unbox = TRUE)
  })
  srv <- webfakes::new_app_process(app)
  on.exit(srv$stop(), add = TRUE)

  # 503 is in the retry set, so this also proves the retry policy runs against
  # a real server and gives up rather than hanging or masking the status.
  expect_error(
    suppressMessages(fetch_interviews(live_http_conn(srv$url("/")))),
    "API request failed \\[503\\]"
  )
})

# --- pagination over real HTTP — HTTP-05..07 ---------------------------------

test_that("a RELATIVE Link target is resolved and followed (HTTP-05)", {
  # The defect this file was written to catch, and one no mock could: a mocked
  # response is never requested, so a `Link` target that cannot be turned into
  # a request looks perfectly fine. RFC 8288 permits a relative target; left
  # unresolved it reached httr2::request() as "/v2/interviews?page=2" and died
  # in curl with no host.
  skip_if_no_webfakes()
  srv <- webfakes::new_app_process(live_http_app(page_size = 10L))
  on.exit(srv$stop(), add = TRUE)

  conn <- live_http_conn(srv$url("/"), pagination = list(style = "link"))
  got <- suppressMessages(fetch_interviews(conn))

  # Compared against the fixture rather than seq_len(): a bus-route design
  # preserves duplicate interview UIDs, so every uid here appears twice and an
  # assertion of uniqueness would be asserting the wrong thing about the data.
  dir <- system.file("calamus-2016", package = "tidycreel")
  want <- utils::read.csv(file.path(dir, "interviews.csv"), stringsAsFactors = FALSE)
  expect_equal(nrow(got), nrow(want))
  expect_equal(sort(got$interview_uid), sort(as.character(want$interview_uid)))
})

test_that("page-style pagination walks the pages over real HTTP (HTTP-06)", {
  skip_if_no_webfakes()
  srv <- webfakes::new_app_process(live_http_app(page_size = 7L))
  on.exit(srv$stop(), add = TRUE)

  conn <- live_http_conn(
    srv$url("/"),
    pagination = list(style = "page", page_param = "page", page_size = 7)
  )
  got <- suppressMessages(fetch_interviews(conn))

  # 24 rows at 7 per page: 7 + 7 + 7 + 3, and the short final page ends it.
  # Every row arrives exactly once -- a page re-requested or skipped shows up
  # as a changed multiset, which duplicate UIDs in this fixture would hide from
  # a uniqueness check.
  dir <- system.file("calamus-2016", package = "tidycreel")
  want <- utils::read.csv(file.path(dir, "interviews.csv"), stringsAsFactors = FALSE)
  expect_equal(nrow(got), nrow(want))
  expect_equal(
    sort(table(got$interview_uid)),
    sort(table(as.character(want$interview_uid))),
    ignore_attr = TRUE
  )
})

test_that("an undeclared paginated response is refused, not truncated (HTTP-07)", {
  # The refusal half of #334, now against a server that really does paginate.
  # Before that fix this returned 10 of 24 interviews and said nothing.
  skip_if_no_webfakes()
  srv <- webfakes::new_app_process(live_http_app(page_size = 10L))
  on.exit(srv$stop(), add = TRUE)

  expect_error(
    suppressMessages(fetch_interviews(live_http_conn(srv$url("/")))),
    "offered another page|total of 24 records"
  )
})

# --- HTTP must not change the data — HTTP-08 ---------------------------------

test_that("an HTTP fetch equals a CSV fetch of the same fixture (HTTP-08)", {
  # The strongest statement available without a real deployment: the same
  # calamus-2016 rows, fetched over a socket and off disk, are identical once
  # they reach canonical form. Anything the transport could corrupt -- a
  # number arriving as text, a date losing its class, a row dropped by the
  # pagination loop, a column left under its raw JSON name -- shows up as a
  # difference here.
  #
  # Deliberately NOT re-asserting the reference totals: those live in
  # test-composition-calamus.R over the CSV path, and duplicating them here
  # would test the estimators a second time rather than the transport once.
  skip_if_no_webfakes()
  srv <- webfakes::new_app_process(live_http_app(page_size = 10L))
  on.exit(srv$stop(), add = TRUE)

  dir <- system.file("calamus-2016", package = "tidycreel")
  csv_conn <- tidycreel.connect::creel_connect(
    list(
      interviews      = file.path(dir, "interviews.csv"),
      counts          = file.path(dir, "counts.csv"),
      catch           = file.path(dir, "catch.csv"),
      harvest_lengths = file.path(dir, "harvest_lengths.csv"),
      release_lengths = file.path(dir, "release_lengths.csv")
    ),
    tidycreel::creel_schema(
      survey_type       = "bus_route",
      interview_uid_col = "interview_uid",
      date_col          = "date",
      site_col          = "site",
      circuit_col       = "circuit",
      effort_col        = "effort_hours",
      trip_status_col   = "trip_status",
      n_counted_col     = "n_counted",
      n_interviewed_col = "n_interviewed",
      bank_anglers_col  = "bank_anglers",
      angler_boats_col  = "angler_boats",
      non_ang_boats_col = "non_ang_boats",
      catch_uid_col     = "catch_uid",
      species_col       = "species",
      catch_count_col   = "catch_count",
      catch_type_col    = "catch_type"
    )
  )
  api_conn <- live_http_conn(srv$url("/"), pagination = list(style = "link"))

  over_http <- suppressMessages(fetch_interviews(api_conn))
  off_disk  <- suppressMessages(fetch_interviews(csv_conn))

  shared <- intersect(names(over_http), names(off_disk))
  expect_true(all(c("interview_uid", "date", "trip_status", "effort") %in% shared))

  # `catch_count` is deliberately not shared: the CSV interviews carry it, the
  # API serves catch from its own endpoint, and the documented API workflow has
  # the caller assemble it. Nothing is lost, it arrives by another route.
  expect_false("catch_count" %in% shared)

  # The uid is compared as text on both sides. It arrives as a JSON string here
  # and is inferred numeric by the CSV reader, and the package passes each
  # source's type through rather than imposing one -- so the SAME survey has a
  # character uid from an API and a numeric uid from CSV. That is a real
  # difference and not this test's to settle; what matters for transport is
  # that the identifiers themselves match.
  over_http$interview_uid <- as.character(over_http$interview_uid)
  off_disk$interview_uid <- as.character(off_disk$interview_uid)
  # Ordered on every shared column, because interview_uid alone is not a total
  # order here -- the fixture repeats each uid -- and a partial key leaves the
  # two frames in different orders for reasons that have nothing to do with
  # transport.
  row_order <- function(df) do.call(order, unname(as.list(df[shared])))
  expect_equal(
    over_http[row_order(over_http), shared, drop = FALSE],
    off_disk[row_order(off_disk), shared, drop = FALSE],
    ignore_attr = TRUE
  )

  counts_http <- suppressMessages(suppressWarnings(fetch_counts(api_conn)))
  counts_disk <- suppressMessages(suppressWarnings(fetch_counts(csv_conn)))
  shared_c <- intersect(names(counts_http), names(counts_disk))
  expect_equal(
    counts_http[order(counts_http$date), shared_c, drop = FALSE],
    counts_disk[order(counts_disk$date), shared_c, drop = FALSE],
    ignore_attr = TRUE
  )
})
