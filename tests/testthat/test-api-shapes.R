# The schema half of GH #330 item 2, reframed.
#
# The original issue asked for one live endpoint. That would have told us
# whether ONE agency's payload decodes, which is not a property of this package
# -- and it left the question blocked behind a credential nobody had. The
# question worth answering is the general one: of the JSON shapes an API is
# entitled to return, which does this connection read correctly, which does it
# refuse, and is there any it reads WRONGLY? Only the third kind matters, and a
# local server can enumerate all three.
#
# See helper-api-shapes.R for the payloads. Every route on that server returns
# the same three records; only the wrapper differs.

# --- shapes that must work ---------------------------------------------------

test_that("a bare JSON array is read as the records (SHAPE-01)", {
  # The control. Every other shape below is compared against this result, so a
  # regression here should fail this test rather than all of them.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  got <- suppressMessages(fetch_counts(api_shapes_conn(srv$url("/"), "bare")))
  expect_equal(as.data.frame(got[, names(api_shapes_expected())]), api_shapes_expected())
})

test_that("an envelope is read when records_path says where to look (SHAPE-02)", {
  # `{"count": 3, "results": [...]}` -- the Django REST Framework shape, and the
  # most common envelope in the wild. Also the control for SHAPE-17/18: `count`
  # here EQUALS the rows returned, so the truncation guard must stay silent.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  conn <- api_shapes_conn(srv$url("/"), "env-results", records_path = "results")
  got  <- suppressMessages(fetch_counts(conn))
  expect_equal(as.data.frame(got[, names(api_shapes_expected())]), api_shapes_expected())
})

test_that("an OData envelope is read the same way (SHAPE-03)", {
  # Different key, no new code path -- the point is that the key is the
  # caller's to name, so nothing about "results" is special.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  conn <- api_shapes_conn(srv$url("/"), "env-value", records_path = "value")
  got  <- suppressMessages(fetch_counts(conn))
  expect_equal(nrow(got), 3L)
})

test_that("a nested envelope is walked one member at a time (SHAPE-04)", {
  # The records sit two members deep, under data and then items.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  conn <- api_shapes_conn(srv$url("/"), "env-nested", records_path = c("data", "items"))
  got  <- suppressMessages(fetch_counts(conn))
  expect_equal(as.data.frame(got[, names(api_shapes_expected())]), api_shapes_expected())
})

test_that("a single record returned as an object is one row (SHAPE-05)", {
  # An API that returns `{...}` rather than `[{...}]` when the filter matches
  # once. Reading it as zero rows would silently drop the only record.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  got <- suppressMessages(fetch_counts(api_shapes_conn(srv$url("/"), "single-object")))
  expect_equal(nrow(got), 1L)
  expect_equal(got$bank_anglers, 4)
})

test_that("quoted numbers arrive as numbers (SHAPE-06)", {
  # Legal JSON, and routine from an API backed by a string-typed column. Left
  # as character, every count would be text and every rate computed on it wrong
  # -- so this asserts the type, not just the value.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  got <- suppressMessages(fetch_counts(api_shapes_conn(srv$url("/"), "string-numbers")))
  expect_type(got$bank_anglers, "double")
  expect_equal(got$bank_anglers, c(4, 0, 7))
})

test_that("an explicit null and an absent key both become NA, never 0 (SHAPE-07)", {
  # The distinction this package exists to protect. Row 2 sends
  # `"FishingBoats": null`, row 3 omits the key entirely, and row 1 sends a
  # genuine 0 in `OtherBoats`. If any of the three collapsed into the others,
  # a count of "no boats seen" and "nobody recorded boats" would be the same
  # number downstream.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  got <- suppressMessages(fetch_counts(api_shapes_conn(srv$url("/"), "nulls")))
  expect_equal(got$angler_boats, c(2, NA, NA))
  expect_equal(got$non_ang_boats, c(0, 0, 1))
  expect_false(any(got$angler_boats == 0, na.rm = TRUE))
})

test_that("a nested member the field map ignores is dropped, not refused (SHAPE-08)", {
  # An `Audit` object riding along on every record is normal and harmless. It
  # must not make the fetch fail: only a field the profile ASKED for has to be
  # a value.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  got <- suppressMessages(fetch_counts(api_shapes_conn(srv$url("/"), "nested-unmapped")))
  expect_equal(nrow(got), 1L)
  expect_false("Audit" %in% names(got))
})

test_that("an empty array and an empty envelope both give zero rows (SHAPE-09)", {
  # Asserted at .api_fetch() rather than fetch_counts(), so an empty result is
  # separated from what the validator then says about a frame with no columns.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  bare <- api_shapes_conn(srv$url("/"), "empty-array")
  expect_equal(nrow(.api_fetch(bare$con, "counts")), 0L)

  env <- api_shapes_conn(srv$url("/"), "empty-envelope", records_path = "results")
  expect_equal(nrow(.api_fetch(env$con, "counts")), 0L)
})

# --- shapes that must be refused ---------------------------------------------

test_that("an undeclared envelope is refused, not flattened (SHAPE-10)", {
  # The silent one, and the reason this file exists. `as.data.frame()` does not
  # fail on `{"data": [...], "meta": {"total": 3}}`: it produces columns named
  # `data.SurveyDate` with `meta.total` recycled down every row. Nothing errors,
  # and the misread reaches the field map looking like unfamiliar column names.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  conn <- api_shapes_conn(srv$url("/"), "env-data-meta")
  expect_error(
    suppressMessages(fetch_counts(conn)),
    "no .*records_path.* is configured"
  )
  # ...and the message says which member to name, or it is not actionable.
  expect_error(suppressMessages(fetch_counts(conn)), "data")
})

test_that("the refusal fires for an envelope that would have errored anyway (SHAPE-11)", {
  # `{"count": 3, "next": null, "results": [...]}` DOES fail under
  # as.data.frame(), with "arguments imply differing number of rows: 1, 0, 3".
  # That is loud but says nothing about what to do, so the envelope check has
  # to run first and name `results`.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  expect_error(
    suppressMessages(fetch_counts(api_shapes_conn(srv$url("/"), "env-results"))),
    "results"
  )
})

test_that("a mapped field holding an object is refused (SHAPE-12)", {
  # `"ShoreAnglers": {"bank": 4, "pier": 1}` parses to a data.frame COLUMN.
  # Carried on it reaches add_counts() where a count was expected, and no
  # numeric coercion touches it on the way.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  expect_error(
    suppressMessages(fetch_counts(api_shapes_conn(srv$url("/"), "nested-object"))),
    "nested JSON"
  )
  # Names both the raw field and the canonical one it was mapped to.
  expect_error(
    suppressMessages(fetch_counts(api_shapes_conn(srv$url("/"), "nested-object"))),
    "ShoreAnglers.*bank_anglers"
  )
})

test_that("a mapped field holding an array is refused (SHAPE-13)", {
  # `"ShoreAnglers": [4, 1]` parses to a list column, which survives every
  # numeric coercion untouched.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  expect_error(
    suppressMessages(fetch_counts(api_shapes_conn(srv$url("/"), "nested-array"))),
    "nested JSON"
  )
})

test_that("records_path naming a member that is not there says what is (SHAPE-14)", {
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  conn <- api_shapes_conn(srv$url("/"), "env-results", records_path = "items")
  expect_error(suppressMessages(fetch_counts(conn)), "no .*items.* member")
  # The message lists the members that ARE present, which is the whole fix.
  expect_error(suppressMessages(fetch_counts(conn)), "results")
})

test_that("records_path against a bare array says to drop it (SHAPE-15)", {
  # The opposite misconfiguration: a profile carrying `records_path` written
  # for a different deployment. Without this it fails as "no results member",
  # pointing at the response rather than at the profile.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  conn <- api_shapes_conn(srv$url("/"), "bare", records_path = "results")
  expect_error(suppressMessages(fetch_counts(conn)), "already a bare JSON array")
})

# --- truncation carried in the body, not the headers -------------------------

test_that("a declared body total larger than the rows aborts (SHAPE-16)", {
  # `{"recordTotal": 9, "results": [3 rows]}` with no pagination style. No
  # header says the response is partial, so the header guard sees nothing:
  # supporting envelopes without reading the body count would have re-opened,
  # for exactly the enveloped APIs, the silent truncation GH #330 is about.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  conn <- api_shapes_conn(
    srv$url("/"), "trunc-declared",
    records_path = "results", total_path = "recordTotal"
  )
  expect_error(
    suppressMessages(fetch_counts(conn)),
    "total of 9 records but returned 3"
  )
})

test_that("an undeclared but conventionally-named total also aborts (SHAPE-17)", {
  # `{"count": 9, "results": [3 rows]}` with no total_path. The name is guessed
  # -- but only ever to REFUSE, never to decide what to return, so a wrong
  # guess cannot put a number in a result. Compare SHAPE-02, where the same
  # `count` key equals the row count and nothing is raised.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  conn <- api_shapes_conn(srv$url("/"), "trunc-guessed", records_path = "results")
  expect_error(
    suppressMessages(fetch_counts(conn)),
    "total of 9 records but returned 3"
  )
})

# --- configuration ------------------------------------------------------------

test_that("total_path without records_path is refused at construction (SHAPE-18)", {
  # It would silently do nothing: the body total is only read inside an
  # envelope, so accepting it would leave a profile that looks configured for
  # the truncation check and is not.
  expect_error(
    api_shapes_conn("http://example.invalid/", "bare", total_path = "count"),
    "without.*records_path"
  )
})

test_that("records_path must be member names (SHAPE-19)", {
  expect_error(
    api_shapes_conn("http://example.invalid/", "bare", records_path = 1L),
    "character vector of member names"
  )
  expect_error(
    api_shapes_conn("http://example.invalid/", "bare", records_path = ""),
    "character vector of member names"
  )
})

test_that("a YAML profile can declare the response shape (SHAPE-20)", {
  # The documented route into every other setting is a profile file, so a
  # response shape that can only be set in R is a feature the docs cannot
  # actually recommend (the gap GH #128 and #171 both closed for other keys).
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  path <- withr::local_tempfile(fileext = ".yml")
  writeLines(c(
    "default:",
    "  backend: api",
    paste0("  base_url: ", srv$url("/")),
    "  uid_param: survey_id",
    "  creel_uids: [shape-test]",
    "  records_path: results",
    "  total_path: count",
    "  endpoints:",
    "    counts: env-results",
    "  field_map:",
    "    counts:",
    "      date: SurveyDate",
    "      bank_anglers: ShoreAnglers",
    "      angler_boats: FishingBoats",
    "      non_ang_boats: OtherBoats",
    "  schema:",
    "    survey_type: instantaneous"
  ), path)

  conn <- creel_connect_from_yaml(path)
  got  <- suppressMessages(fetch_counts(conn))
  expect_equal(as.data.frame(got[, names(api_shapes_expected())]), api_shapes_expected())
})

# --- found by the pre-push ensemble review ------------------------------------

test_that("a single record carrying a metadata object is not an envelope (SHAPE-21)", {
  # Two models independently caught this in review. The envelope check first
  # asked only "does a member hold a container", which is true of `Audit` on an
  # ordinary record -- so `{"SurveyDate": ..., "Audit": {...}}` was refused as a
  # wrapper, naming Audit as the records. It reads correctly on the previous
  # release, so this is a regression guard rather than a new capability.
  #
  # The array form of the same payload (SHAPE-08) never hit it: jsonlite
  # simplifies `[{...}]` to a data.frame, which short-circuits the check.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  got <- suppressMessages(fetch_counts(api_shapes_conn(srv$url("/"), "single-nested")))
  expect_equal(nrow(got), 1L)
  expect_equal(got$bank_anglers, 4)
  expect_false("Audit" %in% names(got))
})

test_that("a nested envelope is still caught one level down (SHAPE-22)", {
  # The control for SHAPE-21. Distinguishing a record's metadata object from a
  # wrapper must not go so far that `{"data": {"items": [...]}}` stops being
  # recognised -- that is the shape records_path exists for.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  expect_error(
    suppressMessages(fetch_counts(api_shapes_conn(srv$url("/"), "env-nested"))),
    "no .*records_path.* is configured"
  )
})

test_that("a quoted body total still aborts (SHAPE-23)", {
  # `{"count": "9", ...}`. The X-Total-Count guard has always run as.numeric()
  # over its header text, so reading only R-numeric body totals would have made
  # the refusal depend on how the API happened to type a number -- and the
  # failure mode of that is the silent truncation the guard exists to stop.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  conn <- api_shapes_conn(srv$url("/"), "trunc-string", records_path = "results")
  expect_error(
    suppressMessages(fetch_counts(conn)),
    "total of 9 records but returned 3"
  )
})

test_that("a total_path that resolves to nothing aborts (SHAPE-24)", {
  # A declared setting that quietly does nothing is worse than one that is
  # missing: the profile looks guarded. Same stance as pagination, which
  # refuses an unknown setting rather than ignoring it.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  conn <- api_shapes_conn(
    srv$url("/"), "trunc-guessed",
    records_path = "results", total_path = "totl"
  )
  expect_error(suppressMessages(fetch_counts(conn)), "no .*totl.* member")
})

test_that("a total_path naming something that is not a number aborts (SHAPE-25)", {
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  conn <- api_shapes_conn(
    srv$url("/"), "env-results",
    records_path = "results", total_path = "results"
  )
  expect_error(
    suppressMessages(fetch_counts(conn)),
    "total_path.* does not name a number"
  )
})

# --- cursor pagination (GH #330; unblocked by records_path) -------------------

test_that("a cursor carrying a whole URL is followed to the end (CUR-01)", {
  # Three pages of one record each, chained by a `next` in the response BODY.
  # The old code refused this style by name because the pointer had nowhere to
  # be read from; records_path is what changed that.
  #
  # The pointer is deliberately RELATIVE, which no mocked response can exercise:
  # a mock never performs the follow-up, so a target that cannot be turned into
  # a request looks healthy. Same trap as the Link header in #345.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  conn <- api_shapes_conn(
    srv$url("/"), "cur-url",
    records_path = "results",
    pagination   = list(style = "cursor", next_path = "next")
  )
  got <- suppressMessages(fetch_counts(conn))

  expect_equal(as.data.frame(got[, names(api_shapes_expected())]), api_shapes_expected())
})

test_that("a whole-URL cursor is requested verbatim, filter included (CUR-01b)", {
  # Review flagged that a URL pointer replaces the request rather than adding to
  # it, so anything the API leaves out of the next URL is left out. That is the
  # documented contract and matches `style = "link"` -- the API builds the URL,
  # so the API owns what is in it. Pinned rather than changed: the fixture now
  # emits the filter the way a real API does, and the server reports whether it
  # arrived, so a regression to a filter-losing request fails here.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  conn <- api_shapes_conn(
    srv$url("/"), "cur-url",
    records_path = "results",
    pagination   = list(style = "cursor", next_path = "next")
  )
  raw <- .api_fetch(conn$con, "counts")
  expect_true("SawFilter" %in% names(raw))
  expect_equal(nrow(raw), 3L)
  expect_equal(raw$SawFilter, rep(TRUE, 3L))
})

test_that("a cursor carrying an opaque token is sent back as its parameter (CUR-02)", {
  # The other real flavour: the body holds `"next": "t2"`, not a URL, and the
  # token goes back on the ORIGINAL request as ?after=t2. Getting all three
  # records is only possible if each token was actually sent.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  conn <- api_shapes_conn(
    srv$url("/"), "cur-token",
    records_path = "results",
    pagination   = list(style = "cursor", next_path = "next", cursor_param = "after")
  )
  got <- suppressMessages(fetch_counts(conn))

  expect_equal(nrow(got), 3L)
  expect_equal(got$bank_anglers, c(4, 0, 7))
})

test_that("the uid filter survives every page turn (CUR-03)", {
  # A token sent by REPLACING the request would drop `survey_id`, and an API
  # reading a missing filter as "every survey" returns other surveys' rows --
  # a wrong dataset carrying no sign that it is wrong. The server reports back
  # whether it saw the filter, so this cannot pass by accident.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  conn <- api_shapes_conn(
    srv$url("/"), "cur-token",
    records_path = "results",
    pagination   = list(style = "cursor", next_path = "next", cursor_param = "after")
  )
  raw <- .api_fetch(conn$con, "counts")
  # Assert the column EXISTS and has a row per page before asserting its value:
  # a flag that never arrived is NULL, and `all(NULL)` is TRUE, so the obvious
  # form of this test passes without checking anything.
  expect_true("SawFilter" %in% names(raw))
  expect_equal(nrow(raw), 3L)
  expect_equal(raw$SawFilter, rep(TRUE, 3L))
})

test_that("a next_path that names nothing on page one aborts (CUR-04)", {
  # The mistyped-setting case. Treating an absent pointer as "done" would end
  # the fetch after page one and return it as the complete dataset -- the exact
  # silent truncation this whole feature exists to prevent, and the same defect
  # the review found in total_path on #347.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  conn <- api_shapes_conn(
    srv$url("/"), "cur-nonext",
    records_path = "results",
    pagination   = list(style = "cursor", next_path = "next")
  )
  expect_error(
    suppressMessages(fetch_counts(conn)),
    "first response has no .*next.* member"
  )
  # The message must say what IS there, or it is not actionable.
  expect_error(suppressMessages(fetch_counts(conn)), "results")
})

test_that("a cursor that points back at the same page aborts (CUR-05)", {
  # A chain that never advances would bind the same rows over and over and
  # inflate every total. Caught by the existing identical-pages guard, asserted
  # here because a cursor loop is a different way of reaching it than a Link one.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  conn <- api_shapes_conn(
    srv$url("/"), "cur-loop",
    records_path = "results",
    pagination   = list(style = "cursor", next_path = "next")
  )
  expect_error(
    suppressMessages(fetch_counts(conn)),
    "identical rows for two consecutive pages"
  )
})

test_that("a cursor page_size is sent, and does not end the loop early (CUR-06)", {
  # Review found page_size accepted for `cursor` and then dropped on the floor —
  # the exact "silently ignored setting" the pagination validator refuses
  # everywhere else. It is stored and sent now.
  #
  # But the short-page stop rule is NOT applied to a cursor: the pointer is
  # authoritative, and an API may return a short page while still offering a
  # next one. Each page here holds 1 record against a declared size of 2, so a
  # length-based stop would return 1 of 3 and call it complete.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  conn <- api_shapes_conn(
    srv$url("/"), "cur-token",
    records_path = "results",
    pagination   = list(
      style = "cursor", next_path = "next", cursor_param = "after",
      page_size = 2, page_size_param = "limit"
    )
  )
  raw <- .api_fetch(conn$con, "counts")
  # The size actually reached the wire. Asserting only the row count cannot
  # tell a dropped page_size from a sent one, because both return all 3.
  expect_true("SawLimit" %in% names(raw))
  expect_equal(raw$SawLimit, rep(TRUE, 3L))
  # ...and every record still arrived: each page holds 1 against a declared 2,
  # so a length-based stop would have returned 1 of 3 and called it complete.
  expect_equal(nrow(raw), 3L)
})

test_that("a cursor loop names the pointer, not an offset parameter (CUR-07)", {
  # The duplicate-page abort assumed any non-link style was page or offset, so a
  # cursor loop produced "It appears to ignore the parameter." with no parameter
  # named — a message that tells you nothing about which setting to look at.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  conn <- api_shapes_conn(
    srv$url("/"), "cur-loop",
    records_path = "results",
    pagination   = list(style = "cursor", next_path = "next")
  )
  expect_error(
    suppressMessages(fetch_counts(conn)),
    "next.* pointer leads back to the page it came from"
  )
})

# --- HTTP status semantics (GH #349) -----------------------------------------

test_that("every transient status is retried, not aborted (STATUS-01)", {
  # Before this, only 429 and 503 were transient. A 502 from a load balancer, a
  # 504 from a slow upstream, a 408 -- each aborted the whole fetch on the first
  # try, and for a paginated fetch that discards the pages already collected.
  #
  # Each route fails once and then succeeds, so recovering the records IS the
  # proof that a second request was made.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  for (code in api_shapes_status_codes()) {
    conn <- api_shapes_conn(srv$url("/"), sprintf("status%d", code))
    got  <- suppressMessages(fetch_counts(conn))
    expect_equal(nrow(got), 3L, info = paste("status", code))
  }
})

test_that("425 is transient too, though no local server can serve it (STATUS-01b)", {
  # webfakes answers "Unknown HTTP response code: 425" with a 500. Because 500
  # is now transient itself, a 425 route would recover and the test would look
  # green having never served a 425 -- passing for the wrong reason. So the
  # predicate is asserted directly, and the gap in coverage is stated rather
  # than papered over.
  expect_true(425L %in% tidycreel.connect:::.api_transient_statuses())
  # The set is a deliberate list, not "every 4xx/5xx": a 404 must stay permanent.
  expect_false(404L %in% tidycreel.connect:::.api_transient_statuses())
})

test_that("a permanent status aborts on the first request (STATUS-02)", {
  # The other half, and the one that keeps STATUS-01 from being "retry
  # everything". A 404 or a 401 will say the same thing three times; retrying
  # only triples the wait before the user sees it.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  for (code in api_shapes_permanent_codes()) {
    conn <- api_shapes_conn(srv$url("/"), sprintf("perm%d", code))
    expect_error(
      suppressMessages(fetch_counts(conn)),
      sprintf("API request failed \\[%d\\]", code)
    )
    # ...and exactly once. The server counts its own hits, so this measures the
    # retry rather than inferring it from how long the failure took.
    n <- httr2::resp_body_json(
      httr2::req_perform(httr2::request(paste0(srv$url("/"), "attempts?key=p", code)))
    )$n
    expect_equal(n, 1L, info = paste("status", code))
  }
})

test_that("a 429 waits the interval the server asked for (STATUS-03)", {
  # httr2 reads Retry-After itself, so this is not code this package had to
  # write -- but #349 recorded it as unhandled, and the only way to know which
  # is true is to make a server ask for a wait and time it. Two seconds
  # requested against a sub-second default backoff.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  conn    <- api_shapes_conn(srv$url("/"), "retry-after")
  started <- Sys.time()
  got     <- suppressMessages(fetch_counts(conn))
  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))

  expect_equal(nrow(got), 3L)
  # Generous lower bound: the point is that it waited SECONDS rather than
  # httr2's default sub-second first backoff, not that it waited exactly 2.
  expect_gt(elapsed, 1.5)
})

test_that("a 200 carrying an error document is refused, quoting it (STATUS-04)", {
  # The one with teeth. Nothing is wrong at the HTTP layer, so
  # .api_check_status() never sees it. Read as data, the object becomes one
  # record, every mapped field misses, and the fetch dies at the validator
  # saying "date: column missing" -- blaming the field map for a fault in the
  # request. The API said "invalid survey_id" and the package said "your
  # configuration is wrong".
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  conn <- api_shapes_conn(srv$url("/"), "ok-error")
  expect_error(
    suppressMessages(fetch_counts(conn)),
    "returned an error document with status 200"
  )
  # The API's own words have to survive into the message, or the user still has
  # to go and look.
  expect_error(suppressMessages(fetch_counts(conn)), "invalid survey_id")
  # And it must NOT be the old misdiagnosis. Asserted on the captured message
  # rather than as a negative-lookahead pattern: the abort is multi-line, and
  # `^(?!...)$` anchors to the first line only, so that form would pass whether
  # or not the phrase appeared further down.
  msg <- tryCatch(
    suppressMessages(fetch_counts(conn)),
    error = function(e) conditionMessage(e)
  )
  expect_false(grepl("column missing", msg, fixed = TRUE))
})

test_that("a real record carrying a message field is not an error document (STATUS-05)", {
  # The false-positive guard, and the reason the check needs all three
  # conditions. `message` is a perfectly ordinary field name. What makes a body
  # an error document is that it carries one AND none of the fields the profile
  # asked for -- here every one of them is present.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  got <- suppressMessages(fetch_counts(api_shapes_conn(srv$url("/"), "ok-message")))
  expect_equal(nrow(got), 1L)
  expect_equal(got$bank_anglers, 4)
})

test_that("an envelope annotated with a message is not an error document (STATUS-06)", {
  # Found by the pre-push review, and a regression I introduced: with
  # `records_path` set, the mapped fields live INSIDE the envelope, so looking
  # for them at the top level finds none. `{"results": [...], "message": "..."}`
  # -- a successful response with a note attached -- was refused, which would
  # have broken exactly the enveloped and cursor APIs #347 and #348 added.
  #
  # A records member that resolves is proof the body carries records, whatever
  # sits beside it.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  conn <- api_shapes_conn(srv$url("/"), "env-message", records_path = "results")
  got  <- suppressMessages(fetch_counts(conn))
  expect_equal(nrow(got), 3L)
  expect_equal(got$bank_anglers, c(4, 0, 7))
})

test_that("an enveloped API reporting an error is quoted, not 'no member' (STATUS-07)", {
  # The other side of STATUS-06, and why the error check still runs before the
  # extraction. When `records_path` does NOT resolve and the body carries an
  # error, the useful message is the API's own -- not "the response has no
  # results member", which describes the symptom and hides the cause.
  skip_if_no_shapes_server()
  srv <- api_shapes_server()

  conn <- api_shapes_conn(srv$url("/"), "ok-error", records_path = "results")
  expect_error(suppressMessages(fetch_counts(conn)), "invalid survey_id")
  msg <- tryCatch(
    suppressMessages(fetch_counts(conn)),
    error = function(e) conditionMessage(e)
  )
  expect_false(grepl("has no", msg, fixed = TRUE))
})
