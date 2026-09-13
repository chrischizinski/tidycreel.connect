# A real HTTP server that returns the same three records in many JSON shapes.
#
# `helper-live-http.R` answers "does this package speak HTTP at all", using the
# calamus fixture so the numbers at the far end are validated ones. This file
# answers a different question -- "does it survive the shapes an arbitrary API
# is entitled to return" -- and for that the payload should be as small and as
# uninteresting as possible: when a shape test fails it must be the shape that
# failed, not the arithmetic.
#
# So the records here are invented, three rows wide enough to fetch and no
# wider. Every route serves LITERAL JSON rather than a serialised data.frame,
# because the byte layout is the thing under test and toJSON()'s choices about
# unboxing and null are not.
#
# The raw field names are deliberately not tidycreel's canonical names, so the
# rename in `.rename_api_to_canonical()` has to do real work.

# The three records every shape carries, as the canonical frame they should
# arrive as once fetched. Shapes that deliberately corrupt or omit a value say
# so in their own test.
api_shapes_expected <- function() {
  data.frame(
    date          = as.Date(c("2016-05-14", "2016-05-15", "2016-05-16")),
    bank_anglers  = c(4, 0, 7),
    angler_boats  = c(2, 1, 3),
    non_ang_boats = c(0, 0, 1),
    stringsAsFactors = FALSE
  )
}

# The record array, as literal JSON. Kept as one string so every envelope below
# wraps exactly the same bytes and a difference between two shape tests can only
# be the wrapper.
api_shapes_records_json <- function() {
  # nolint start: quotes_linter. JSON literals are single-quoted so the double
  # quotes inside them stay readable -- the exact bytes are what is under test.
  paste0(
    '[',
    '{"SurveyDate":"2016-05-14","ShoreAnglers":4,"FishingBoats":2,"OtherBoats":0},',
    '{"SurveyDate":"2016-05-15","ShoreAnglers":0,"FishingBoats":1,"OtherBoats":0},',
    '{"SurveyDate":"2016-05-16","ShoreAnglers":7,"FishingBoats":3,"OtherBoats":1}',
    ']'
  )
  # nolint end
}

# Every shape this package might be pointed at, keyed by the route that serves
# it. The names are the endpoint paths the tests configure.
api_shapes_bodies <- function() {
  # nolint start: quotes_linter. Same reason as above.
  recs <- api_shapes_records_json()
  list(
    # --- shapes that must WORK -------------------------------------------
    # The body is the array. What every existing test assumes.
    "bare"             = recs,
    # Django REST Framework, and the most common envelope there is.
    "env-results"      = sprintf('{"count":3,"next":null,"previous":null,"results":%s}', recs),
    # JSON:API / Laravel: records under `data`, everything else under `meta`.
    # Without records_path this one does not error -- it flattens into columns
    # named `data.SurveyDate` with `meta.total` recycled down every row.
    "env-data-meta"    = sprintf('{"data":%s,"meta":{"total":3}}', recs),
    # OData.
    "env-value"        = sprintf('{"@odata.count":3,"value":%s}', recs),
    # Two levels deep.
    "env-nested"       = sprintf('{"data":{"items":%s},"status":"ok"}', recs),
    # A single record returned as an object rather than a one-element array.
    "single-object"    = '{"SurveyDate":"2016-05-14","ShoreAnglers":4,"FishingBoats":2,"OtherBoats":0}',
    # Quoted numbers. Legal JSON, common from APIs backed by a string-typed
    # column, and the fetch loaders coerce them.
    "string-numbers"   = paste0(
      '[',
      '{"SurveyDate":"2016-05-14","ShoreAnglers":"4","FishingBoats":"2","OtherBoats":"0"},',
      '{"SurveyDate":"2016-05-15","ShoreAnglers":"0","FishingBoats":"1","OtherBoats":"0"},',
      '{"SurveyDate":"2016-05-16","ShoreAnglers":"7","FishingBoats":"3","OtherBoats":"1"}',
      ']'
    ),
    # An explicit null in row 2 and the same key simply absent from row 3.
    # Both mean "not recorded" and both must arrive as NA, never as 0.
    "nulls"            = paste0(
      '[',
      '{"SurveyDate":"2016-05-14","ShoreAnglers":4,"FishingBoats":2,"OtherBoats":0},',
      '{"SurveyDate":"2016-05-15","ShoreAnglers":0,"FishingBoats":null,"OtherBoats":0},',
      '{"SurveyDate":"2016-05-16","ShoreAnglers":7,"OtherBoats":1}',
      ']'
    ),
    # A nested member the field map never asks for. Dropped like any other
    # unmapped column, not refused.
    "nested-unmapped"  = paste0(
      '[',
      '{"SurveyDate":"2016-05-14","ShoreAnglers":4,"FishingBoats":2,"OtherBoats":0,',
      '"Audit":{"by":"jd","at":"2016-05-14T09:00:00Z"}}',
      ']'
    ),
    # One record as an object, carrying a metadata object the field map never
    # asks for. The array form of this is "nested-unmapped" above; the bare
    # object form is the one an envelope check can mistake for an envelope.
    "single-nested"    = paste0(
      '{"SurveyDate":"2016-05-14","ShoreAnglers":4,"FishingBoats":2,"OtherBoats":0,',
      '"Audit":{"by":"jd","at":"2016-05-14T09:00:00Z"}}'
    ),
    "empty-array"      = '[]',
    "empty-envelope"   = '{"count":0,"results":[]}',

    # --- shapes that must be REFUSED --------------------------------------
    # A mapped field that is an object rather than a value.
    "nested-object"    = paste0(
      '[{"SurveyDate":"2016-05-14","ShoreAnglers":{"bank":4,"pier":1},',
      '"FishingBoats":2,"OtherBoats":0}]'
    ),
    # A mapped field that is an array rather than a value.
    "nested-array"     = paste0(
      '[{"SurveyDate":"2016-05-14","ShoreAnglers":[4,1],',
      '"FishingBoats":2,"OtherBoats":0}]'
    ),
    # Three of nine records, with the total declared in the body. No header
    # says so, so only reading the envelope can catch it.
    "trunc-declared"   = sprintf('{"recordTotal":9,"results":%s}', recs),
    # The same truncation under a conventionally-named key the profile did not
    # declare.
    "trunc-guessed"    = sprintf('{"count":9,"results":%s}', recs),
    # The same truncation with the total QUOTED. Legal JSON, and the header
    # twin has always coerced its text, so the body must too.
    "trunc-string"     = sprintf('{"count":"9","results":%s}', recs)
  )
  # nolint end
}

# The three records again, one JSON object per element, so the cursor routes
# below can hand back exactly one per page.
api_shapes_rows_json <- function() {
  # nolint start: quotes_linter. As above.
  c(
    '{"SurveyDate":"2016-05-14","ShoreAnglers":4,"FishingBoats":2,"OtherBoats":0}',
    '{"SurveyDate":"2016-05-15","ShoreAnglers":0,"FishingBoats":1,"OtherBoats":0}',
    '{"SurveyDate":"2016-05-16","ShoreAnglers":7,"FishingBoats":3,"OtherBoats":1}'
  )
  # nolint end
}

# The statuses a flaky-but-working API emits. Every one of these is a GET here,
# so a retry cannot duplicate a side effect.
#
# 425 is deliberately ABSENT: webfakes cannot emit it ("Unknown HTTP response
# code: 425") and answers 500 instead. Since 500 is itself transient now, a 425
# route would recover and the test would pass without ever having served a 425.
# It is asserted against the predicate directly in STATUS-01b instead.
api_shapes_status_codes <- function() {
  c(408L, 429L, 500L, 502L, 503L, 504L)
}

# Statuses that mean the request itself was wrong, and must NOT be retried.
api_shapes_permanent_codes <- function() {
  c(400L, 401L, 403L, 404L, 422L)
}

api_shapes_app <- function() {
  app <- webfakes::new_app()
  app$locals$bodies <- api_shapes_bodies()
  app$locals$rows   <- api_shapes_rows_json()
  # Request counters for the status routes. An environment, because the handler
  # runs in a subprocess and needs somewhere mutable that survives between
  # requests within it.
  app$locals$seen   <- new.env(parent = emptyenv())
  for (shape in names(api_shapes_bodies())) {
    local({
      key <- shape
      app$get(paste0("/", key), function(req, res) {
        res$
          set_header("Content-Type", "application/json")$
          send(charToRaw(res$app$locals$bodies[[key]]))
      })
    })
  }
  # --- status routes ---------------------------------------------------
  # Each /status<code> route fails once with that code and then succeeds, so a
  # test can tell "retried and recovered" from "aborted" by the RESULT rather
  # than by counting requests.
  for (code in api_shapes_status_codes()) {
    local({
      cc <- code
      app$get(sprintf("/status%d", cc), function(req, res) {
        seen <- res$app$locals$seen
        key  <- as.character(cc)
        n    <- (if (is.null(seen[[key]])) 0L else seen[[key]]) + 1L
        seen[[key]] <- n
        if (n < 2L) {
          res$
            set_status(cc)$
            set_header("Content-Type", "application/json")$
            send(charToRaw(sprintf('{"transient":true,"try":%d}', n)))
        } else {
          res$
            set_header("Content-Type", "application/json")$
            send(charToRaw(sprintf("[%s]", paste(res$app$locals$rows, collapse = ","))))
        }
      })
    })
  }

  # Permanent failures: these always fail, and the count is reported in the body
  # so a test can prove the request was made ONCE. A retried 404 is three times
  # the latency for the same answer.
  for (code in api_shapes_permanent_codes()) {
    local({
      cc <- code
      app$get(sprintf("/perm%d", cc), function(req, res) {
        seen <- res$app$locals$seen
        key  <- paste0("p", cc)
        n    <- (if (is.null(seen[[key]])) 0L else seen[[key]]) + 1L
        seen[[key]] <- n
        res$
          set_status(cc)$
          set_header("Content-Type", "application/json")$
          send(charToRaw(sprintf('{"attempts":%d}', n)))
      })
    })
  }

  # Reports how many times a route was hit, so "retried" is measured rather
  # than inferred from timing.
  app$get("/attempts", function(req, res) {
    key <- req$query[["key"]]
    n   <- res$app$locals$seen[[key]]
    res$
      set_header("Content-Type", "application/json")$
      send(charToRaw(sprintf('{"n":%d}', if (is.null(n)) 0L else n)))
  })

  # A 429 that names its own wait. httr2 reads Retry-After itself; the route
  # exists so that fact is pinned rather than believed.
  app$get("/retry-after", function(req, res) {
    seen <- res$app$locals$seen
    n <- (if (is.null(seen[["ra"]])) 0L else seen[["ra"]]) + 1L
    seen[["ra"]] <- n
    if (n < 2L) {
      res$
        set_status(429L)$
        set_header("Retry-After", "2")$
        set_header("Content-Type", "application/json")$
        send(charToRaw('{"throttled":true}'))
    } else {
      res$
        set_header("Content-Type", "application/json")$
        send(charToRaw(sprintf("[%s]", paste(res$app$locals$rows, collapse = ","))))
    }
  })

  # A 200 whose body is an error object, not data. .api_check_status() never
  # sees this, because nothing is wrong at the HTTP layer.
  app$get("/ok-error", function(req, res) {
    res$
      set_header("Content-Type", "application/json")$
      send(charToRaw('{"error":"invalid survey_id","code":4001}'))
  })

  # A successful ENVELOPE with an informational note beside the records. The
  # mapped fields are inside `results`, so nothing the field map names appears
  # at the top level -- which is what made this look like an error document.
  app$get("/env-message", function(req, res) {
    res$
      set_header("Content-Type", "application/json")$
      send(charToRaw(sprintf(
        '{"results":[%s],"message":"partial day"}',
        paste(res$app$locals$rows, collapse = ",")
      )))
  })

  # The false-positive guard: a real record that happens to carry a `message`
  # field, alongside the fields the profile actually asked for.
  app$get("/ok-message", function(req, res) {
    res$
      set_header("Content-Type", "application/json")$
      send(charToRaw(paste0(
        '{"SurveyDate":"2016-05-14","ShoreAnglers":4,"FishingBoats":2,',
        '"OtherBoats":0,"message":"partial day"}'
      )))
  })

  # --- cursor routes ---------------------------------------------------
  # Stateless: the page is derived from the request, so a loop that fails to
  # advance repeats a page rather than quietly running off the end.

  # The pointer is a whole URL, and deliberately RELATIVE -- RFC-legal, emitted
  # by real servers, and unreachable by any mock.
  app$get("/cur-url", function(req, res) {
    rows <- res$app$locals$rows
    p <- req$query[["p"]]
    p <- if (is.null(p)) 1L else as.integer(p)
    # Relative AND carrying the caller's filter, which is what a real API emits:
    # the next URL is requested verbatim, so whatever the API leaves out of it is
    # left out of the request. A server that dropped its own filter here would
    # hand back other surveys' rows, and no code on this side could tell.
    sid <- req$query[["survey_id"]]
    nxt <- if (p < length(rows)) {
      sprintf('"/cur-url?survey_id=%s&p=%d"', if (is.null(sid)) "" else sid, p + 1L)
    } else {
      "null"
    }
    row <- sub("\\}$", sprintf(',"SawFilter":%s}', if (is.null(sid)) "false" else "true"),
               rows[[p]])
    res$
      set_header("Content-Type", "application/json")$
      send(charToRaw(sprintf('{"results":[%s],"next":%s}', row, nxt)))
  })

  # The pointer is an opaque token, sent back as ?after=. The uid filter has to
  # survive the page turn, so the handler records whether it saw it.
  app$get("/cur-token", function(req, res) {
    rows  <- res$app$locals$rows
    after <- req$query[["after"]]
    p <- if (is.null(after)) 1L else as.integer(sub("^t", "", after))
    nxt <- if (p < length(rows)) sprintf('"t%d"', p + 1L) else "null"
    saw <- if (is.null(req$query[["survey_id"]])) "false" else "true"
    # Reported per row so a declared page_size that never reaches the wire is
    # visible in the RESULT. Row count alone cannot see it: a size that is
    # dropped and a size that is sent but does not stop the loop both return
    # every record.
    lim <- if (is.null(req$query[["limit"]])) "false" else "true"
    # Spliced INTO the record, not left as a sibling of it: records_path strips
    # every sibling before the frame is built, so a flag reported beside the
    # records would arrive as NULL and `all(NULL)` is TRUE -- an assertion that
    # cannot fail. See the vacuous-assertion trap.
    row <- sub("\\}$", sprintf(',"SawFilter":%s,"SawLimit":%s}', saw, lim), rows[[p]])
    res$
      set_header("Content-Type", "application/json")$
      send(charToRaw(sprintf('{"results":[%s],"next":%s}', row, nxt)))
  })

  # No `next` member at all. On the FIRST page that is a mistyped next_path,
  # not the end of the data.
  app$get("/cur-nonext", function(req, res) {
    res$
      set_header("Content-Type", "application/json")$
      send(charToRaw(sprintf(
        '{"results":[%s]}', paste(res$app$locals$rows, collapse = ",")
      )))
  })

  # A pointer that never advances.
  app$get("/cur-loop", function(req, res) {
    res$
      set_header("Content-Type", "application/json")$
      send(charToRaw(sprintf(
        '{"results":[%s],"next":"/cur-loop"}', res$app$locals$rows[[1L]]
      )))
  })

  app
}

api_shapes_field_map <- function() {
  list(
    counts = list(
      date          = "SurveyDate",
      bank_anglers  = "ShoreAnglers",
      angler_boats  = "FishingBoats",
      non_ang_boats = "OtherBoats"
    )
  )
}

# A connection pointed at one shape route. `...` reaches creel_connect_api(),
# so a test adds records_path / total_path / pagination as it needs them.
api_shapes_conn <- function(base_url, shape, ...) {
  tidycreel.connect::creel_connect_api(
    base_url      = base_url,
    creel_uids    = "shape-test",
    schema        = tidycreel::creel_schema(survey_type = "instantaneous"),
    uid_param     = "survey_id",
    endpoints     = list(counts = shape),
    api_field_map = api_shapes_field_map(),
    ...
  )
}

skip_if_no_shapes_server <- function() {
  testthat::skip_if_not_installed("webfakes")
  testthat::skip_if_not_installed("tidycreel")
}

# One server for the whole shape file. Every shape is a different route on the
# same app, so the thing varying between these tests is the response body and
# nothing else -- and starting fifteen subprocesses to prove that would be slow
# for no gain.
api_shapes_server <- local({
  srv <- NULL
  function() {
    if (is.null(srv)) {
      srv <<- webfakes::new_app_process(api_shapes_app())
      withr::defer(srv$stop(), envir = testthat::teardown_env())
    }
    srv
  }
})
