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
