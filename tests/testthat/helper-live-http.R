# A real HTTP server, for the half of this package the mocks cannot reach.
#
# Every other API test here uses httr2::local_mocked_responses(), which
# intercepts BEFORE the HTTP layer: `req_perform()` never runs. That exercises
# the field mapping and the validators, and none of the transport. Until this
# file, nothing in the package had ever performed a request -- so the retry and
# error policies, the JSON deserialisation, the `Link` header parser, the
# pagination loop and the auth header had all been asserted only against
# responses this package constructed for itself.
#
# webfakes serves the calamus-2016 fixture as JSON over a real socket. The
# payload is real survey data and the expected answers are the validated
# reference outputs, so these tests assert the whole chain -- request, parse,
# rename, design, estimate -- against numbers that were not invented here.
#
# What this still does NOT cover, and #330 item 2 remains open for: a real
# deployment's schema. No local server can tell you another agency named a field
# something you did not expect.

# The JSON keys below are invented, as everywhere else in this package's tests.
# They are deliberately NOT the canonical tidycreel names, so the rename in
# `.rename_api_to_canonical()` has to do real work rather than passing columns
# through untouched.
live_http_app <- function(page_size = 10L) {
  dir <- system.file("calamus-2016", package = "tidycreel")

  app <- webfakes::new_app()
  app$locals$interviews <- utils::read.csv(
    file.path(dir, "interviews.csv"), stringsAsFactors = FALSE
  )
  app$locals$counts <- utils::read.csv(
    file.path(dir, "counts.csv"), stringsAsFactors = FALSE
  )
  app$locals$catch <- utils::read.csv(
    file.path(dir, "catch.csv"), stringsAsFactors = FALSE
  )
  app$locals$page_size <- page_size
  app$locals$token <- "live-http-test-token"

  # Auth on every route. A wrong or absent token is a 401, so the test that
  # asserts the Authorization header is sent cannot pass by accident.
  app$use(function(req, res) {
    if (!identical(req$get_header("Authorization"),
                   paste("Bearer", res$app$locals$token))) {
      res$set_status(401L)$send_json(
        list(error = "missing or wrong bearer token"), auto_unbox = TRUE
      )
      return()
    }
    "next"
  })

  app$get("/v2/interviews", function(req, res) {
    iv <- res$app$locals$interviews
    per <- res$app$locals$page_size
    pg <- req$query[["page"]]
    page <- if (is.null(pg)) 1L else as.integer(pg)
    i0 <- (page - 1L) * per + 1L
    i1 <- min(page * per, nrow(iv))
    rows <- if (i0 > nrow(iv)) iv[0, , drop = FALSE] else iv[i0:i1, , drop = FALSE]
    out <- data.frame(
      InterviewID    = as.character(rows$interview_uid),
      SurveyDate     = rows$date,
      TripStatus     = rows$trip_status,
      HoursFished    = rows$effort_hours,
      SiteName       = rows$site,
      CircuitName    = rows$circuit,
      AnglersCounted = rows$n_counted,
      AnglersAsked   = rows$n_interviewed,
      stringsAsFactors = FALSE
    )
    if (i1 < nrow(iv)) {
      # Deliberately RELATIVE. RFC 8288 permits it, servers emit it, and it is
      # what no mocked response could ever exercise: a mock never performs the
      # follow-up request, so a target that cannot be requested looks fine.
      res$set_header(
        "Link", sprintf('</v2/interviews?page=%d>; rel="next"', page + 1L)
      )
    }
    res$set_header("X-Total-Count", as.character(nrow(iv)))
    res$send_json(out, dataframe = "rows", auto_unbox = TRUE)
  })

  app$get("/v2/counts", function(req, res) {
    ct <- res$app$locals$counts
    res$send_json(
      data.frame(
        SurveyDate   = ct$date,
        ShoreAnglers = ct$bank_anglers,
        FishingBoats = ct$angler_boats,
        OtherBoats   = ct$non_ang_boats,
        stringsAsFactors = FALSE
      ),
      dataframe = "rows", auto_unbox = TRUE
    )
  })

  app$get("/v2/catch", function(req, res) {
    ca <- res$app$locals$catch
    res$send_json(
      data.frame(
        InterviewID   = as.character(ca$interview_uid),
        SpeciesCode   = as.character(ca$species),
        FishCount     = ca$catch_count,
        CatchCategory = ca$catch_type,
        stringsAsFactors = FALSE
      ),
      dataframe = "rows", auto_unbox = TRUE
    )
  })

  app
}

live_http_field_map <- function() {
  list(
    interviews = list(
      interview_uid = "InterviewID",
      date          = "SurveyDate",
      trip_status   = "TripStatus",
      effort_hours  = "HoursFished",
      site          = "SiteName",
      circuit       = "CircuitName",
      n_counted     = "AnglersCounted",
      n_interviewed = "AnglersAsked"
    ),
    counts = list(
      date          = "SurveyDate",
      bank_anglers  = "ShoreAnglers",
      angler_boats  = "FishingBoats",
      non_ang_boats = "OtherBoats"
    ),
    catch = list(
      interview_uid = "InterviewID",
      species       = "SpeciesCode",
      catch_count   = "FishCount",
      catch_type    = "CatchCategory"
    )
  )
}

live_http_conn <- function(base_url, pagination = NULL, token = "live-http-test-token") {
  tidycreel.connect::creel_connect_api(
    base_url      = base_url,
    creel_uids    = c("calamus-2016-a", "calamus-2016-b"),
    schema        = tidycreel::creel_schema(survey_type = "bus_route"),
    uid_param     = "survey_id",
    endpoints     = list(
      interviews = "v2/interviews",
      counts     = "v2/counts",
      catch      = "v2/catch"
    ),
    auth          = list(type = "bearer", token = token),
    api_field_map = live_http_field_map(),
    pagination    = pagination
  )
}

skip_if_no_webfakes <- function() {
  testthat::skip_if_not_installed("webfakes")
  testthat::skip_if_not_installed("tidycreel")
  if (!nzchar(system.file("calamus-2016", package = "tidycreel"))) {
    testthat::skip("calamus-2016 fixture not available from the installed tidycreel")
  }
}
