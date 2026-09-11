# Tests for API pagination — GH #330.
#
# `.api_fetch()` used to perform one request and return its body as the whole
# dataset. Against a paginated endpoint that returns page 1 and nothing else:
# fewer interviews and fewer counts reach the design, every total is understated
# in proportion to what was dropped, and nothing errors or warns. These tests
# pin both halves of the fix — following a declared style to exhaustion, and
# refusing a response that can be proven partial when no style is declared.

# --- refusing a provably partial response (no style declared) — PAG-01..05 ----

test_that("an undeclared paginated response aborts rather than returning page 1 (PAG-01)", {
  # The discriminating case: before the fix this returned one row and called it
  # the complete dataset. `Link: rel="next"` is the API stating outright that
  # there is more, so returning it cannot be defended as a judgement call.
  httr2::local_mocked_responses(function(req) {
    test_api_page(
      "A1",
      'Link: <http://test.example.com/api/v2/interviews?page=2>; rel="next"'
    )
  })
  conn <- make_api_conn()
  expect_error(
    fetch_interviews(conn),
    "offered another page and no pagination style is configured"
  )
})

test_that("an X-Total-Count larger than the rows returned aborts (PAG-02)", {
  # The other thing an API can say plainly: it holds 50 records and sent 2.
  httr2::local_mocked_responses(function(req) {
    test_api_page(c("A1", "A2"), "X-Total-Count: 50")
  })
  conn <- make_api_conn()
  expect_error(fetch_interviews(conn), "total of 50 records but returned 2")
})

test_that("an X-Total-Count equal to the rows returned is not a truncation (PAG-03)", {
  # The guard must not fire on a complete response that happens to report its
  # size, or every API sending the header becomes unusable.
  httr2::local_mocked_responses(function(req) {
    test_api_page(c("A1", "A2"), "X-Total-Count: 2")
  })
  conn   <- make_api_conn()
  result <- fetch_interviews(conn)
  expect_equal(nrow(result), 2L)
})

test_that("a response advertising nothing is returned unchanged (PAG-04)", {
  # The behaviour every existing caller depends on: one page, no headers, no
  # pagination configured, no new failure.
  httr2::local_mocked_responses(function(req) {
    test_api_page(c("A1", "A2", "A3"))
  })
  conn   <- make_api_conn()
  result <- fetch_interviews(conn)
  expect_equal(nrow(result), 3L)
})

test_that("style 'none' still refuses a next link (PAG-05)", {
  # Declaring `none` states that this API does not paginate. A Link header says
  # it does, so the declaration is wrong -- and trusting a wrong declaration
  # returns exactly the truncated dataset this feature exists to prevent.
  httr2::local_mocked_responses(function(req) {
    test_api_page(
      "A1",
      'Link: <http://test.example.com/api/v2/interviews?page=2>; rel="next"'
    )
  })
  conn <- make_api_conn(pagination = list(style = "none"))
  expect_error(fetch_interviews(conn), "offered another page")
})

# --- following a declared style — PAG-06..09 ---------------------------------

test_that("style 'page' fetches every page and sends the page parameter (PAG-06)", {
  # Fails on the old code, which returned 2 of the 5 rows. Both halves are
  # asserted: the rows that arrive, and that the page number was really sent --
  # a loop that requested page 1 three times would also produce 5 rows if the
  # mock advanced on its own.
  seen <- character()
  page <- 0L
  httr2::local_mocked_responses(function(req) {
    seen <<- c(seen, req$url)
    page <<- page + 1L
    ids  <- list(c("A1", "A2"), c("A3", "A4"), "A5", character())[[page]]
    test_api_page(ids)
  })
  conn   <- make_api_conn(pagination = list(style = "page", page_param = "page"))
  result <- fetch_interviews(conn)

  expect_equal(nrow(result), 5L)
  expect_equal(result$interview_uid, c("A1", "A2", "A3", "A4", "A5"))
  expect_match(seen[1], "page=1")
  expect_match(seen[2], "page=2")
  expect_match(seen[3], "page=3")
})

test_that("style 'page' sends page_size when a parameter name is given (PAG-06b)", {
  seen <- character()
  n    <- 0L
  httr2::local_mocked_responses(function(req) {
    seen <<- c(seen, req$url)
    n    <<- n + 1L
    test_api_page(if (n == 1L) c("A1", "A2") else "A3")
  })
  conn <- make_api_conn(pagination = list(
    style = "page", page_param = "page",
    page_size = 2, page_size_param = "per_page"
  ))
  result <- fetch_interviews(conn)

  # page_size doubles as the stop rule, so a full page is followed by another
  # request and a short one ends the loop.
  expect_match(seen[1], "per_page=2")
  expect_match(seen[2], "per_page=2")
  expect_equal(nrow(result), 3L)
})

test_that("style 'offset' advances by the rows actually received (PAG-07)", {
  # Advancing by an assumed page size would skip real records the moment a page
  # comes back short, so the offset is driven by what arrived, not what was
  # asked for.
  seen <- character()
  page <- 0L
  httr2::local_mocked_responses(function(req) {
    seen <<- c(seen, req$url)
    page <<- page + 1L
    ids  <- list(c("A1", "A2", "A3"), c("A4", "A5"), character())[[page]]
    test_api_page(ids)
  })
  conn   <- make_api_conn(pagination = list(style = "offset", offset_param = "offset"))
  result <- fetch_interviews(conn)

  expect_equal(nrow(result), 5L)
  expect_match(seen[1], "offset=0")
  expect_match(seen[2], "offset=3")
  expect_match(seen[3], "offset=5")
})

test_that("style 'link' follows the header chain to its end (PAG-08)", {
  # The next link is an absolute URL the API built, so it is requested verbatim
  # -- re-applying the uid filter would fight whatever the API put in it.
  seen <- character()
  httr2::local_mocked_responses(list(
    test_api_page(
      c("A1", "A2"),
      'Link: <http://test.example.com/api/v2/interviews?cursor=abc>; rel="next"'
    ),
    test_api_page(c("A3", "A4")),
    test_api_page("A5")
  ))
  conn   <- make_api_conn(pagination = list(style = "link"))
  result <- fetch_interviews(conn)

  # Two responses consumed, not three: the second carries no next link.
  expect_equal(nrow(result), 4L)
  expect_equal(result$interview_uid, c("A1", "A2", "A3", "A4"))
})

test_that("a Link header is split on the element boundary, not on every comma (PAG-08b)", {
  # A creel request joins its uids with commas, so the next URL contains commas
  # of its own. Splitting the header on "," would cut that URL in half and the
  # follow-up would 404 -- or worse, fetch a different filter's rows.
  link <- paste0(
    '<http://test.example.com/api/v2/interviews?survey_id=u-1,u-2&page=1>; rel="prev", ',
    '<http://test.example.com/api/v2/interviews?survey_id=u-1,u-2&page=2>; rel="next"'
  )
  resp <- test_api_page("A1", paste0("Link: ", link))
  expect_equal(
    tidycreel.connect:::.api_next_link(resp),
    "http://test.example.com/api/v2/interviews?survey_id=u-1,u-2&page=2"
  )
})

test_that("a short page ends the loop without a further request (PAG-09)", {
  n <- 0L
  httr2::local_mocked_responses(function(req) {
    n <<- n + 1L
    test_api_page(if (n == 1L) c("A1", "A2") else "A3")
  })
  conn   <- make_api_conn(pagination = list(style = "page", page_param = "page", page_size = 2))
  result <- fetch_interviews(conn)

  expect_equal(nrow(result), 3L)
  expect_equal(n, 2L)
})

# --- refusing a bad paging loop — PAG-10..13 ---------------------------------

test_that("hitting max_pages aborts and returns nothing (PAG-10)", {
  # A partial dataset must not be returnable, so the cap aborts rather than
  # handing back the pages collected so far.
  i <- 0L
  httr2::local_mocked_responses(function(req) {
    i <<- i + 1L
    test_api_page(paste0("A", i))
  })
  conn <- make_api_conn(pagination = list(
    style = "page", page_param = "page", max_pages = 3
  ))
  expect_error(fetch_interviews(conn), "Stopped after 3 pages")
})

test_that("an API ignoring the page parameter aborts naming it (PAG-11)", {
  # The commonest misconfiguration: the parameter is called something else, so
  # every request returns page 1. Binding those pages would duplicate every
  # record and inflate every total.
  httr2::local_mocked_responses(function(req) {
    test_api_page(c("A1", "A2"))
  })
  conn <- make_api_conn(pagination = list(style = "page", page_param = "pagenum"))
  expect_error(fetch_interviews(conn), "ignore the pagenum parameter")
})

test_that("pages describing different fields abort rather than bind (PAG-12)", {
  n <- 0L
  httr2::local_mocked_responses(function(req) {
    n <<- n + 1L
    body <- if (n == 1L) {
      '[{"InterviewID":"A1","SurveyDate":"2016-03-28","TripStatus":"complete","HoursFished":2,"MinutesFished":30}]'
    } else if (n == 2L) {
      '[{"InterviewID":"A2","SurveyDate":"2016-03-29","TripStatus":"complete"}]'
    } else {
      "[]"
    }
    httr2::response(200, headers = "Content-Type: application/json", body = charToRaw(body))
  })
  conn <- make_api_conn(pagination = list(style = "page", page_param = "page"))
  expect_error(fetch_interviews(conn), "do not describe the same fields")
})

test_that("pages listing the same fields in a different order still bind (PAG-13)", {
  # JSON object key order is free to vary between pages, and a fetch that
  # refused on order alone would fail against a perfectly well-behaved API.
  n <- 0L
  httr2::local_mocked_responses(function(req) {
    n <<- n + 1L
    body <- if (n == 1L) {
      '[{"InterviewID":"A1","SurveyDate":"2016-03-28","TripStatus":"complete","HoursFished":2,"MinutesFished":30}]'
    } else if (n == 2L) {
      '[{"SurveyDate":"2016-03-29","MinutesFished":0,"InterviewID":"A2","HoursFished":3,"TripStatus":"complete"}]'
    } else {
      "[]"
    }
    httr2::response(200, headers = "Content-Type: application/json", body = charToRaw(body))
  })
  conn   <- make_api_conn(pagination = list(style = "page", page_param = "page"))
  result <- fetch_interviews(conn)

  expect_equal(nrow(result), 2L)
  expect_equal(result$interview_uid, c("A1", "A2"))
  # The reordered page's values stayed with their own fields: 2h30m and 3h00m,
  # which a mis-aligned bind would not reproduce.
  expect_equal(result$effort, c(2.5, 3))
})

# --- the declaration itself — PAG-14..18 -------------------------------------

test_that("an unknown pagination setting is refused, not ignored (PAG-14)", {
  # A silently dropped setting leaves the caller believing the API is being
  # paged when it is not -- the same failure with an extra layer of confidence.
  expect_error(
    make_api_conn(pagination = list(style = "page", page_param = "page", pagesize = 100)),
    "Unknown pagination setting"
  )
})

test_that("style 'page' requires the parameter name (PAG-15)", {
  expect_error(
    make_api_conn(pagination = list(style = "page")),
    "pagination\\$page_param.*is required"
  )
})

test_that("style 'offset' requires the parameter name (PAG-15b)", {
  expect_error(
    make_api_conn(pagination = list(style = "offset")),
    "pagination\\$offset_param.*is required"
  )
})

test_that("style 'cursor' is refused by name with its reason (PAG-16)", {
  # Deferred rather than half-built: a cursor arrives in a response envelope
  # this backend does not read. Accepting the style and fetching page 1 would
  # be the defect wearing a configuration.
  expect_error(
    make_api_conn(pagination = list(style = "cursor", cursor_param = "after")),
    "must be one of"
  )
})

test_that("page_size_param without page_size is refused (PAG-17)", {
  expect_error(
    make_api_conn(pagination = list(
      style = "page", page_param = "page", page_size_param = "per_page"
    )),
    "with no .*page_size"
  )
})

test_that("a pagination list with no style is refused (PAG-18)", {
  expect_error(
    make_api_conn(pagination = list(page_param = "page")),
    "must be a named list with a .*style.* entry"
  )
})

test_that("max_pages must be a whole number of at least one (PAG-18b)", {
  expect_error(
    make_api_conn(pagination = list(style = "link", max_pages = 0)),
    "max_pages.*whole number"
  )
})

# --- the declaration reaches the connection — PAG-19 --------------------------

test_that("a YAML profile's pagination block reaches the connection (PAG-19)", {
  # The route the documentation recommends. Without this the feature is
  # reachable only by hand-building a connection, which is not how a deployment
  # is meant to be configured.
  skip_if_not_installed("config")
  path <- withr::local_tempfile(fileext = ".yml")
  writeLines(c(
    "default:",
    "  backend: api",
    '  base_url: "http://test.example.com/api/"',
    '  uid_param: "survey_id"',
    "  creel_uids:",
    '    - "test-uid-001"',
    "  pagination:",
    "    style: page",
    '    page_param: "page"',
    "    page_size: 250",
    '    page_size_param: "per_page"',
    "  endpoints:",
    '    interviews: "v2/interviews"',
    "  field_map:",
    "    interviews:",
    '      interview_uid: "InterviewID"',
    '      date: "SurveyDate"',
    '      trip_status: "TripStatus"',
    '      effort_hours: "HoursFished"',
    "  schema:",
    "    survey_type: instantaneous"
  ), path)

  conn <- creel_connect_from_yaml(path)
  expect_equal(conn$con$pagination$style, "page")
  expect_equal(conn$con$pagination$page_param, "page")
  expect_equal(conn$con$pagination$page_size, 250L)
  expect_equal(conn$con$pagination$max_pages, 1000L)
})

# --- settings that would silently disagree with each other — PAG-20..22 -------

test_that("a paging parameter named like uid_param is refused (PAG-20)", {
  # httr2's req_url_query() replaces rather than appends, so the paging value
  # would overwrite the survey filter: `?survey_id=<uid>` becomes `?survey_id=1`.
  # An API reading a missing filter as "every survey" then returns other
  # surveys' rows -- a wrong dataset carrying no sign that it is wrong.
  expect_error(
    make_api_conn(pagination = list(style = "page", page_param = "survey_id")),
    "names the same query parameter as"
  )
})

test_that("two paging settings naming the same parameter are refused (PAG-20b)", {
  expect_error(
    make_api_conn(pagination = list(
      style = "page", page_param = "p", page_size = 50, page_size_param = "p"
    )),
    "name the same query parameter"
  )
})

test_that("a non-finite or out-of-range count is refused, not stored as NA (PAG-21)", {
  # Inf and 1e12 both pass a trunc() test and then become NA at as.integer().
  # A stored NA does not surface until mid-fetch, as base R's "missing value
  # where TRUE/FALSE needed" -- an error naming nothing the caller set.
  expect_error(
    make_api_conn(pagination = list(style = "link", max_pages = Inf)),
    "must be a single whole number"
  )
  expect_error(
    make_api_conn(pagination = list(style = "link", max_pages = 1e12)),
    "must be a single whole number"
  )
})

test_that("a Link chain that repeats a page aborts instead of binding it twice (PAG-22)", {
  # A next link pointing back at the page it came from repeats as silently as a
  # paging parameter the API ignores. If such a chain then ends, the duplicated
  # rows would be bound with nothing said and every total inflated.
  n <- 0L
  httr2::local_mocked_responses(function(req) {
    n <<- n + 1L
    hdr <- if (n < 3L) {
      'Link: <http://test.example.com/api/v2/interviews?page=1>; rel="next"'
    } else {
      character()
    }
    test_api_page(c("A1", "A2"), hdr)
  })
  conn <- make_api_conn(pagination = list(style = "link"))
  expect_error(fetch_interviews(conn), "identical rows for two consecutive pages")
})
