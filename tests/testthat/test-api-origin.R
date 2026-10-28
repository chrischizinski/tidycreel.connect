# Requests go only to the origin of base_url, over HTTPS (#30).
#
# Every request carries the connection's credential. Before #30 a next-page URL
# was followed wherever it pointed, credential attached, and curl's redirect
# handling forwarded an API-key header to whatever host a `Location` named
# (curl strips only `Authorization` on a cross-host redirect). Either way a
# server the user never named could collect the token. These tests pin that it
# cannot, and that refusing is loud: a fetch that silently stopped or went on
# without the credential would return part of the data as though it were all.

# A server that counts the requests reaching its data route and remembers the
# credential headers they carried. It stands in for "somewhere else": the test
# asks it afterwards what it saw, which is the only proof nothing leaked.
origin_sink_app <- function() {
  app <- webfakes::new_app()
  app$locals$hits <- 0L
  app$locals$headers <- character()
  app$get("/v2/interviews", function(req, res) {
    res$app$locals$hits <- res$app$locals$hits + 1L
    # Handlers run in the server's own process, so no test helper is in
    # reach here; base R only.
    for (h in c("Authorization", "X-API-Key")) {
      v <- req$get_header(h)
      res$app$locals$headers <- c(res$app$locals$headers, if (is.null(v)) "" else v)
    }
    res$send_json(list(), auto_unbox = TRUE)
  })
  app$get("/seen", function(req, res) {
    res$send_json(
      list(hits = res$app$locals$hits, headers = res$app$locals$headers),
      auto_unbox = TRUE
    )
  })
  app
}

origin_sink_seen <- function(srv) {
  httr2::resp_body_json(httr2::req_perform(httr2::request(srv$url("/seen"))))
}

origin_conn <- function(base_url, auth, pagination = NULL) {
  tidycreel.connect::creel_connect_api(
    base_url      = base_url,
    creel_uids    = "s-1",
    schema        = tidycreel::creel_schema(survey_type = "instantaneous"),
    uid_param     = "survey_id",
    endpoints     = list(interviews = "v2/interviews"),
    api_field_map = list(interviews = test_api_field_map()$interviews),
    auth          = auth,
    pagination    = pagination
  )
}

# --- next pages --------------------------------------------------------------

test_that("a Link header to another server aborts, and that server gets nothing", {
  skip_if_not_installed("webfakes")
  sink <- webfakes::new_app_process(origin_sink_app())
  on.exit(sink$stop(), add = TRUE)

  home <- webfakes::new_app()
  home$locals$elsewhere <- sink$url("/v2/interviews?page=2")
  home$locals$body <- test_api_interview_json(c("a", "b"))
  home$get("/v2/interviews", function(req, res) {
    res$set_header("Link", sprintf('<%s>; rel="next"', res$app$locals$elsewhere))
    res$set_header("Content-Type", "application/json")
    res$send(res$app$locals$body)
  })
  srv <- webfakes::new_app_process(home)
  on.exit(srv$stop(), add = TRUE)

  conn <- origin_conn(
    srv$url("/"),
    auth = list(type = "bearer", token = "origin-test-token"),
    pagination = list(style = "link")
  )
  expect_error(
    suppressMessages(fetch_interviews(conn)),
    class = "creel_error_api_cross_origin"
  )
  # The point of the fix: not one request reached the other server, so it
  # never saw the token. An abort raised AFTER the request would pass the
  # expect_error() above and fail here.
  expect_equal(origin_sink_seen(sink)$hits, 0L)
})

test_that("a next-page URL in the body naming another server aborts before any request", {
  seen <- character()
  httr2::local_mocked_responses(function(req) {
    seen <<- c(seen, req$url)
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body = charToRaw(paste0(
        '{"results":', test_api_interview_json(c("a", "b")),
        ',"next":"https://elsewhere.example.org/api/v2/interviews?cursor=2"}'
      ))
    )
  })
  conn <- creel_connect_api(
    base_url      = "https://test.example.com/api/",
    creel_uids    = "s-1",
    schema        = tidycreel::creel_schema(survey_type = "instantaneous"),
    uid_param     = "survey_id",
    endpoints     = test_api_endpoints(),
    api_field_map = test_api_field_map(),
    auth          = list(type = "bearer", token = "origin-test-token"),
    pagination    = list(style = "cursor", next_path = "next"),
    records_path  = "results"
  )
  err <- expect_error(
    suppressMessages(fetch_interviews(conn)),
    class = "creel_error_api_cross_origin"
  )
  expect_length(seen, 1L)
  # The foreign origin is named so the user can see where the API pointed, but
  # not the full URL, whose query can carry a cursor or a key.
  expect_match(conditionMessage(err), "https://elsewhere.example.org:443")
  expect_no_match(conditionMessage(err), "cursor=2")
})

test_that("a next page that only drops to http on the same host is another origin", {
  # Same host, different scheme: the token would cross the network in clear.
  httr2::local_mocked_responses(function(req) {
    test_api_page(
      c("a", "b"),
      'Link: <http://test.example.com/api/v2/interviews?page=2>; rel="next"'
    )
  })
  conn <- make_api_conn(pagination = list(style = "link"))
  expect_error(
    suppressMessages(fetch_interviews(conn)),
    class = "creel_error_api_cross_origin"
  )
})

# --- redirects ---------------------------------------------------------------

test_that("a redirect to another server aborts, and the API key never reaches it", {
  # Fails without #30: curl followed the 302 itself and sent X-API-Key along,
  # because it strips only Authorization when a redirect changes host.
  skip_if_not_installed("webfakes")
  sink <- webfakes::new_app_process(origin_sink_app())
  on.exit(sink$stop(), add = TRUE)

  home <- webfakes::new_app()
  home$locals$elsewhere <- sink$url("/v2/interviews")
  home$get("/v2/interviews", function(req, res) {
    res$redirect(res$app$locals$elsewhere, 302L)
  })
  srv <- webfakes::new_app_process(home)
  on.exit(srv$stop(), add = TRUE)

  conn <- origin_conn(
    srv$url("/"),
    auth = list(type = "api_key", key = "origin-test-key")
  )
  expect_error(
    suppressMessages(fetch_interviews(conn)),
    class = "creel_error_api_cross_origin"
  )
  seen <- origin_sink_seen(sink)
  expect_equal(seen$hits, 0L)
  expect_false("origin-test-key" %in% unlist(seen$headers))
})

test_that("a redirect within the origin is followed, credential included", {
  skip_if_not_installed("webfakes")
  home <- webfakes::new_app()
  home$locals$body <- test_api_interview_json(c("a", "b", "c"))
  home$get("/old/v2/interviews", function(req, res) {
    res$redirect("/v2/interviews", 301L)
  })
  home$get("/v2/interviews", function(req, res) {
    if (!identical(req$get_header("X-API-Key"), "origin-test-key")) {
      res$set_status(401L)$send_json(list(error = "no key"), auto_unbox = TRUE)
      return()
    }
    res$set_header("Content-Type", "application/json")
    res$send(res$app$locals$body)
  })
  srv <- webfakes::new_app_process(home)
  on.exit(srv$stop(), add = TRUE)

  conn <- origin_conn(
    srv$url("/old/"),
    auth = list(type = "api_key", key = "origin-test-key")
  )
  # Three rows means the hop was followed AND the key was sent on it; a
  # dropped key is a 401 and an unfollowed redirect is no rows.
  expect_equal(nrow(suppressMessages(fetch_interviews(conn))), 3L)
})

test_that("a redirect loop stops rather than hanging", {
  skip_if_not_installed("webfakes")
  home <- webfakes::new_app()
  home$get("/v2/interviews", function(req, res) {
    res$redirect("/v2/interviews", 302L)
  })
  srv <- webfakes::new_app_process(home)
  on.exit(srv$stop(), add = TRUE)

  expect_error(
    suppressMessages(fetch_interviews(origin_conn(srv$url("/"), auth = NULL))),
    "redirected .* more than 5 times"
  )
})

# --- base_url ----------------------------------------------------------------

test_that("plain http to a remote host is refused unless allow_http = TRUE", {
  args <- list(
    creel_uids    = "s-1",
    schema        = tidycreel::creel_schema(survey_type = "instantaneous"),
    uid_param     = "survey_id",
    endpoints     = test_api_endpoints(),
    api_field_map = test_api_field_map()
  )
  expect_error(
    do.call(creel_connect_api, c(list(base_url = "http://test.example.com/api/"), args)),
    "plain .*http://"
  )
  # The opt-in works, and says what it costs every time.
  expect_warning(
    conn <- do.call(
      creel_connect_api,
      c(list(base_url = "http://test.example.com/api/", allow_http = TRUE), args)
    ),
    class = "creel_warning_api_plain_http"
  )
  expect_s3_class(conn, "creel_connection_api")
  # Loopback never leaves the machine: accepted, and silent.
  for (u in c("http://127.0.0.1:8080/", "http://localhost/", "http://[::1]:9000/")) {
    expect_no_warning(do.call(creel_connect_api, c(list(base_url = u), args)))
  }
})

test_that("base_url must be an absolute https URL with no credential in it", {
  args <- list(
    creel_uids    = "s-1",
    schema        = tidycreel::creel_schema(survey_type = "instantaneous"),
    uid_param     = "survey_id",
    endpoints     = test_api_endpoints(),
    api_field_map = test_api_field_map()
  )
  for (u in c("test.example.com/api/", "ftp://test.example.com/")) {
    expect_error(
      do.call(creel_connect_api, c(list(base_url = u), args)),
      "absolute .*https://.* URL"
    )
  }
  err <- expect_error(
    do.call(
      creel_connect_api,
      c(list(base_url = "https://someone:hunter2@test.example.com/api/"), args)
    ),
    "user name or password"
  )
  # Refused without echoing the URL, which holds the password.
  expect_no_match(conditionMessage(err), "hunter2")
  expect_error(
    do.call(
      creel_connect_api,
      c(list(base_url = "https://test.example.com/api/", allow_http = "yes"), args)
    ),
    "allow_http"
  )
})

test_that("origins compare scheme, host and port, filling default ports", {
  expect_identical(
    .api_origin("https://Test.Example.com/a?x=1"),
    .api_origin("https://test.example.com:443/b")
  )
  expect_false(identical(
    .api_origin("https://test.example.com/"),
    .api_origin("https://test.example.com:8443/")
  ))
  expect_false(identical(
    .api_origin("https://test.example.com/"),
    .api_origin("http://test.example.com/")
  ))
})

test_that("a profile can opt in to plain http, and it warns", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  yaml_path <- withr::local_tempfile(fileext = ".yml")
  writeLines(c(
    "default:",
    "  backend: api",
    '  base_url: "http://test.example.com/api/"',
    "  allow_http: true",
    '  uid_param: "survey_id"',
    "  creel_uids:",
    '    - "s-1"',
    "  schema:",
    "    survey_type: instantaneous",
    "  endpoints:",
    '    interviews: "v2/interviews"',
    "  field_map:",
    "    interviews:",
    '      interview_uid: "InterviewID"',
    '      date: "SurveyDate"'
  ), yaml_path)
  expect_warning(
    creel_connect_from_yaml(yaml_path),
    class = "creel_warning_api_plain_http"
  )
  # And without the key the same profile is refused.
  lines <- readLines(yaml_path)
  writeLines(lines[!grepl("allow_http", lines)], yaml_path)
  expect_error(creel_connect_from_yaml(yaml_path), "plain .*http://")
})
