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

api_shapes_app <- function() {
  app <- webfakes::new_app()
  app$locals$bodies <- api_shapes_bodies()
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
