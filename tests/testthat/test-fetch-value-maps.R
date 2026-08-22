# Source vocabularies through the fetch layer (GH #128).
#
# Every downstream filter matches a canonical literal: "complete" for trip
# filtering, "harvested" for harvest aggregation, "harvest"/"release" for length
# type. A source that codes these columns -- "1"/"2", "H"/"R" -- had no way to
# say what its codes meant, so the caller had to recode by hand between the
# fetch and add_interviews(). That hand recode is the risk: an undeclared third
# code gets folded into whichever of the two the caller happened to think of,
# and nothing says so.
#
# These tests pin the translation, and pin that an undeclared code is refused
# rather than passed along.

make_coded_csv <- function(trip_types = c("1", "2", "1", "1")) {
  dir <- withr::local_tempdir(.local_envir = parent.frame())

  interviews <- data.frame(
    interview_uid = 1L:4L,
    date          = as.Date("2024-06-01") + 0:3,
    catch_count   = c(3L, 0L, 4L, 1L),
    effort_hours  = c(2.5, 1.0, 3.0, 2.0),
    TripKind      = trip_types,
    stringsAsFactors = FALSE
  )
  counts <- data.frame(
    date         = as.Date("2024-06-01") + 0:3,
    bank_anglers = c(12L, 8L, 6L, 10L),
    stringsAsFactors = FALSE
  )
  catch <- data.frame(
    catch_uid     = 1L:2L,
    interview_uid = c(1L, 1L),
    species       = "walleye",
    catch_count   = c(2L, 1L),
    CatchCategory     = c("H", "R"),
    stringsAsFactors = FALSE
  )
  lengths <- data.frame(
    length_uid    = 1L,
    interview_uid = 1L,
    species       = "walleye",
    length_mm     = 450.0,
    LengthType    = "H",
    stringsAsFactors = FALSE
  )

  paths <- list(
    interviews      = file.path(dir, "interviews.csv"),
    counts          = file.path(dir, "counts.csv"),
    catch           = file.path(dir, "catch.csv"),
    harvest_lengths = file.path(dir, "harvest_lengths.csv"),
    release_lengths = file.path(dir, "release_lengths.csv")
  )
  utils::write.csv(interviews, paths$interviews, row.names = FALSE)
  utils::write.csv(counts, paths$counts, row.names = FALSE)
  utils::write.csv(catch, paths$catch, row.names = FALSE)
  utils::write.csv(lengths, paths$harvest_lengths, row.names = FALSE)
  utils::write.csv(lengths, paths$release_lengths, row.names = FALSE)
  paths
}

make_coded_schema <- function(value_maps = NULL) {
  tidycreel::creel_schema(
    survey_type       = "instantaneous",
    interview_uid_col = "interview_uid",
    date_col          = "date",
    catch_col         = "catch_count",
    effort_col        = "effort_hours",
    trip_status_col   = "TripKind",
    bank_anglers_col  = "bank_anglers",
    catch_uid_col     = "catch_uid",
    species_col       = "species",
    catch_count_col   = "catch_count",
    catch_type_col    = "CatchCategory",
    length_uid_col    = "length_uid",
    length_mm_col     = "length_mm",
    length_type_col   = "LengthType",
    value_maps        = value_maps
  )
}

full_maps <- function() {
  list(
    trip_status = c("1" = "complete", "2" = "incomplete"),
    catch_type  = c(H = "harvested", R = "released"),
    length_type = c(H = "harvest", R = "release")
  )
}

# --- CSV backend ---

test_that("fetch_interviews() translates a coded trip_status (GH #128)", {
  conn <- creel_connect(make_coded_csv(), make_coded_schema(full_maps()))
  iv <- suppressMessages(fetch_interviews(conn))

  # Row for row, not merely "the right set of labels somewhere".
  expect_equal(iv$trip_status, c("complete", "incomplete", "complete", "complete"))
})

test_that("fetch_catch() translates a coded catch_type", {
  conn <- creel_connect(make_coded_csv(), make_coded_schema(full_maps()))
  cc <- suppressMessages(fetch_catch(conn))

  expect_equal(cc$catch_type, c("harvested", "released"))
})

test_that("the lengths tables translate a coded length_type", {
  conn <- creel_connect(make_coded_csv(), make_coded_schema(full_maps()))

  expect_equal(suppressMessages(fetch_harvest_lengths(conn))$length_type, "harvest")
  expect_equal(suppressMessages(fetch_release_lengths(conn))$length_type, "harvest")
})

test_that("an undeclared code aborts and names the value (GH #128)", {
  # The regression the issue asks for: a code the map does not cover must never
  # reach a filter that matches canonical literals.
  conn <- creel_connect(
    make_coded_csv(),
    make_coded_schema(list(trip_status = c("1" = "complete")))
  )

  expect_error(
    suppressMessages(fetch_interviews(conn)),
    "does not map"
  )
  # The message names the offending value, so the fix does not require guessing.
  expect_error(
    suppressMessages(fetch_interviews(conn)),
    "2"
  )
})

test_that("values already canonical pass through a partial map", {
  # A source that codes only some rows -- mid-migration, or two field crews with
  # different conventions -- still arrives whole.
  conn <- creel_connect(
    make_coded_csv(trip_types = c("1", "incomplete", "complete", "1")),
    make_coded_schema(list(trip_status = c("1" = "complete")))
  )
  iv <- suppressMessages(fetch_interviews(conn))

  expect_equal(iv$trip_status, c("complete", "incomplete", "complete", "complete"))
})

test_that("no value_maps leaves the fetch exactly as it was", {
  # Declaring a vocabulary is opt-in: a source already speaking canonical values
  # maps nothing and sees no change. This is also what makes the feature safe to
  # add to existing schemas.
  conn <- creel_connect(
    make_coded_csv(trip_types = rep("complete", 4L)),
    make_coded_schema(value_maps = NULL)
  )
  iv <- suppressMessages(fetch_interviews(conn))

  expect_equal(iv$trip_status, rep("complete", 4L))
})

test_that("an unmapped code is refused even when the column is otherwise clean", {
  # NA is left alone -- absence is not a code -- but a real unknown string is
  # not, because it would reach the filter as a literal.
  conn <- creel_connect(
    make_coded_csv(trip_types = c("1", "1", "1", "refused")),
    make_coded_schema(list(trip_status = c("1" = "complete")))
  )

  expect_error(
    suppressMessages(fetch_interviews(conn)),
    "refused"
  )
})

# --- the handoff this protects ---

test_that("a translated frame reaches add_interviews(), which refuses the untranslated one", {
  # Both halves matter. The design layer already refuses a coded vocabulary
  # (validate_trip_metadata()), so the value map is what makes the documented
  # path work rather than what prevents a wrong number.
  paths <- make_coded_csv()
  calendar <- data.frame(
    date     = as.Date("2024-06-01") + 0:3,
    day_type = c("weekday", "weekend", "weekend", "weekday"),
    stringsAsFactors = FALSE
  )

  mapped <- suppressMessages(fetch_interviews(creel_connect(paths, make_coded_schema(full_maps()))))
  design <- suppressWarnings(tidycreel::creel_design(calendar, date = date, strata = day_type))
  expect_no_error(
    suppressWarnings(suppressMessages(tidycreel::add_interviews(
      design, mapped,
      catch = catch_count, effort = effort, trip_status = trip_status
    )))
  )

  unmapped <- suppressMessages(fetch_interviews(creel_connect(paths, make_coded_schema(NULL))))
  expect_error(
    suppressWarnings(suppressMessages(tidycreel::add_interviews(
      design, unmapped,
      catch = catch_count, effort = effort, trip_status = trip_status
    ))),
    "invalid value"
  )
})

# --- API backend ---

test_that("the API backend applies value maps too, and does not warn about them", {
  # value_maps maps a column's values, not its field name, so it is
  # backend-independent -- unlike the column mappings the API path ignores.
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body = charToRaw(paste0(
        '[{"InterviewID":1,"SurveyDate":"2024-06-01","TripStatus":"1","HoursFished":2.5},',
        '{"InterviewID":2,"SurveyDate":"2024-06-02","TripStatus":"2","HoursFished":1.0}]'
      ))
    )
  })
  schema <- tidycreel::creel_schema(
    survey_type = "instantaneous",
    value_maps  = list(trip_status = c("1" = "complete", "2" = "incomplete"))
  )
  # No warning: declaring a vocabulary is not one of the ignored column mappings.
  expect_no_warning(conn <- make_api_conn(schema = schema))

  iv <- suppressMessages(fetch_interviews(conn))
  expect_equal(iv$trip_status, c("complete", "incomplete"))
})

# --- YAML profile route ---

test_that("value_maps survive the YAML profile, which is the documented route", {
  # A feature only reachable by hand-building a schema is not reachable the way
  # the docs tell people to configure a deployment.
  block <- list(trip_status = list("1" = "complete", "2" = "incomplete"))
  vm <- .yaml_value_maps(block)

  expect_type(vm$trip_status, "character")
  expect_equal(vm$trip_status, c("1" = "complete", "2" = "incomplete"))
  # And the result is what creel_schema() accepts, not merely the right shape.
  expect_no_error(tidycreel::creel_schema(survey_type = "instantaneous", value_maps = vm))
})

test_that("a YAML code written unquoted still round-trips", {
  # `1: complete` parses as a number, not a string, and would otherwise reach
  # creel_schema() as an unnamed-looking entry.
  vm <- .yaml_value_maps(list(trip_status = list(`1` = "complete")))

  expect_equal(vm$trip_status, c("1" = "complete"))
})

test_that("a malformed value_maps block explains the shape it wanted", {
  # The message embeds literal YAML braces, which cli reads as an interpolation
  # delimiter unless doubled -- the hint aborted with "Could not evaluate cli {}
  # expression" instead of printing. Only a test on this branch catches it.
  expect_error(.yaml_value_maps(42), "keyed by canonical column")
  expect_error(.yaml_value_maps(42), "trip_status")
})

# --- strata_cols through the same profile ---

test_that("strata_cols survives the YAML profile in mapping form", {
  # Same gap as value_maps and the same consequence: without this a
  # profile-configured counts frame reaches add_counts() with no stratum label
  # and any design built with `strata =` aborts (GH #171).
  sc <- .yaml_strata_cols(list(day_type = "DayTypeCode"))

  expect_type(sc, "character")
  expect_equal(sc, c(day_type = "DayTypeCode"))
  expect_no_error(tidycreel::creel_schema(survey_type = "instantaneous", strata_cols = sc))
})

test_that("a bare YAML sequence names the stratum on both sides", {
  # `strata_cols: [day_type]` parses to an unnamed list, which is the shape
  # meaning "the source already uses the design's name".
  sc <- .yaml_strata_cols(list("day_type"))
  s <- tidycreel::creel_schema(survey_type = "instantaneous", strata_cols = sc)

  expect_equal(s$strata_cols, c(day_type = "day_type"))
})

test_that("two strata round-trip in order", {
  sc <- .yaml_strata_cols(list(day_type = "DayTypeCode", period = "PeriodCode"))

  expect_equal(sc, c(day_type = "DayTypeCode", period = "PeriodCode"))
})

test_that("a malformed strata_cols block explains both accepted shapes", {
  expect_error(.yaml_strata_cols(42), "mapping or a sequence")
  # Both shapes named, and the literal braces actually render.
  expect_error(.yaml_strata_cols(42), "day_type")
})

test_that("a YAML profile's declarations reach a fetch (no {config} needed)", {
  # The public entry point needs {config} to parse the file, which is why the
  # tests in test-creel-connect-yaml.R skip where it is absent. The parsing is
  # the only part {config} does, so feeding the same YAML text through {yaml}
  # exercises the real builder and the real fetch on every machine -- otherwise
  # this path is only ever proven in CI.
  skip_if_not_installed("yaml")

  txt <- paste(c(
    "backend: api",
    'base_url: "https://api.example.org/creel/"',
    'uid_param: "survey_id"',
    "creel_uids:",
    '  - "s-1"',
    "schema:",
    "  survey_type: instantaneous",
    "  strata_cols:",
    '    day_type: "DayTypeCode"',
    "  value_maps:",
    "    trip_status:",
    '      "1": complete',
    '      "2": incomplete',
    "endpoints:",
    '  interviews: "v2/interviews"',
    "field_map:",
    "  interviews:",
    '    interview_uid: "InterviewID"',
    '    date: "SurveyDate"',
    '    trip_status: "TripStatus"',
    '    effort_hours: "HoursFished"',
    '    day_type: "DayTypeCode"'
  ), collapse = "\n")

  conn <- .build_creel_conn(yaml::yaml.load(txt))
  expect_equal(conn$schema$strata_cols, c(day_type = "DayTypeCode"))

  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body = charToRaw(paste0(
        '[{"InterviewID":1,"SurveyDate":"2024-06-01","TripStatus":"1",',
        '"HoursFished":2.5,"DayTypeCode":"weekday"},',
        '{"InterviewID":2,"SurveyDate":"2024-06-02","TripStatus":"2",',
        '"HoursFished":1.0,"DayTypeCode":"weekend"}]'
      ))
    )
  })

  iv <- suppressMessages(fetch_interviews(conn))
  expect_equal(iv$trip_status, c("complete", "incomplete"))
  expect_equal(iv$day_type, c("weekday", "weekend"))
})
