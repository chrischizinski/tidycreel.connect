# Documented corrections (#4, part A). A fix to the data lives in a file with
# its reason, the fetch applies it and says so, and a fix that no longer
# matches anything stops the fetch: the data changed underneath it.

corrections_header <- "creel_uid,table,date,field,from,to,reason"

# A CSV profile over make_test_csv(), with a corrections file beside it.
# `paths` comes from make_test_csv() in the test, whose frame owns the files.
corrections_profile <- function(paths, rows, .env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = .env)
  writeLines(c(corrections_header, rows), file.path(dir, "corrections.csv"))
  yaml_path <- file.path(dir, "profile.yml")
  writeLines(c(
    "default:",
    "  backend: csv",
    "  corrections: corrections.csv",
    "  files:",
    paste0("    ", names(paths), ": ", unlist(paths)),
    "  schema:",
    "    survey_type: instantaneous",
    "    columns:",
    "      effort: effort_hours"
  ), yaml_path)
  yaml_path
}

quiet_fetch <- function(f, conn) suppressMessages(f(conn))

test_that("a correction changes exactly the matching rows, and says so", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  conn <- creel_connect_from_yaml(corrections_profile(
    make_test_csv(),
    ",counts,2024-06-01,bank_anglers,12,14,Recount from the field sheet"
  ))
  expect_message(
    counts <- fetch_counts(conn),
    "line 2, 2024-06-01: bank_anglers on 1 row",
    class = "creel_message_corrections_applied"
  )
  expect_equal(counts$bank_anglers, c(14, 8))
  applied <- attr(counts, "corrections")
  expect_identical(applied$reason, "Recount from the field sheet")
  expect_identical(applied$n_rows, 1L)
})

test_that("corrections apply to interviews, in tidycreel's values", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  conn <- creel_connect_from_yaml(corrections_profile(
    make_test_csv(),
    ",interviews,2024-06-02,trip_status,incomplete,complete,Angler finished"
  ))
  iv <- quiet_fetch(fetch_interviews, conn)
  expect_identical(iv$trip_status, c("complete", "complete"))
})

test_that("the note prints once per connection; the correction applies every time", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  # The corrections describe the source, as the dropped-columns note does:
  # repeated on every fetch they would bury the warnings that matter.
  conn <- creel_connect_from_yaml(corrections_profile(
    make_test_csv(),
    ",counts,2024-06-01,bank_anglers,12,14,Recount"
  ))
  expect_message(fetch_counts(conn), class = "creel_message_corrections_applied")
  expect_no_message(
    again <- fetch_counts(conn),
    class = "creel_message_corrections_applied"
  )
  expect_equal(again$bank_anglers, c(14, 8))
  expect_false(is.null(attr(again, "corrections")))
})

test_that("a correction that matches nothing stops the fetch", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  conn <- creel_connect_from_yaml(corrections_profile(
    make_test_csv(),
    ",counts,2024-06-01,bank_anglers,99,14,Recount"
  ))
  expect_error(
    quiet_fetch(fetch_counts, conn),
    "line 2 matched no counts rows",
    class = "creel_error_correction_unmatched"
  )
})

test_that("a correction naming a column the table lacks stops the fetch", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  conn <- creel_connect_from_yaml(corrections_profile(
    make_test_csv(),
    ",counts,2024-06-01,BankAnglers,12,14,\"Raw name, not tidycreel's\""
  ))
  expect_error(
    quiet_fetch(fetch_counts, conn),
    "does not have",
    class = "creel_error_correction_unmatched"
  )
})

test_that("a correction without a reason is refused when the profile is read", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  expect_error(
    creel_connect_from_yaml(corrections_profile(
      make_test_csv(),
      c(",counts,2024-06-01,bank_anglers,12,14,Recount",
        ",counts,2024-06-02,bank_anglers,8,9,")
    )),
    "no reason on line 3"
  )
})

test_that("malformed rows are refused when the profile is read", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  expect_error(
    creel_connect_from_yaml(corrections_profile(
      make_test_csv(), ",catch,2024-06-01,species,walleye,sauger,Misread"
    )),
    "table other than"
  )
  expect_error(
    creel_connect_from_yaml(corrections_profile(
      make_test_csv(), ",counts,06/01/2024,bank_anglers,12,14,Recount"
    )),
    "not YYYY-MM-DD"
  )
  # A CSV source has no creel label for a named creel to match.
  expect_error(
    creel_connect_from_yaml(corrections_profile(
      make_test_csv(), "lake-a,counts,2024-06-01,bank_anglers,12,14,Recount"
    )),
    "names a .*creel_uid"
  )
})

test_that("an unquoted comma in a reason is refused, not read shifted", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  expect_error(
    creel_connect_from_yaml(corrections_profile(
      make_test_csv(), ",counts,2024-06-01,bank_anglers,12,14,Recount, sheet 2"
    )),
    "different number of fields on line 2"
  )
})

test_that("the note names fields and counts, never the values", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  # A value can be personal (a ZIP code), and the note reaches logs and
  # rendered reports. The values stay in the attribute.
  conn <- creel_connect_from_yaml(corrections_profile(
    make_test_csv(), ",counts,2024-06-01,bank_anglers,12,14567,Recount"
  ))
  msg <- NULL
  counts <- withCallingHandlers(
    fetch_counts(conn),
    creel_message_columns_by_canonical_name = function(m) invokeRestart("muffleMessage"),
    creel_message_corrections_applied = function(m) {
      msg <<- conditionMessage(m)
      invokeRestart("muffleMessage")
    }
  )
  expect_match(msg, "bank_anglers")
  expect_no_match(msg, "14567")
  expect_identical(attr(counts, "corrections")$to, "14567")
})

test_that("NA in a correction stands for a missing value", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  paths <- make_test_csv()
  ct <- utils::read.csv(paths$counts)
  ct$angler_boats[[2]] <- NA
  utils::write.csv(ct, paths$counts, row.names = FALSE)
  conn <- creel_connect_from_yaml(corrections_profile(paths, c(
    ",counts,2024-06-02,angler_boats,NA,3,Filled from the boat log",
    ",counts,2024-06-01,non_ang_boats,0,NA,Sheet illegible"
  )))
  counts <- quiet_fetch(fetch_counts, conn)
  expect_equal(counts$angler_boats, c(0, 3))
  expect_equal(counts$non_ang_boats, c(NA, 0))
})

test_that("line numbers count blank lines and multi-line reasons", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  # The row at fault is on line 6: header, a two-line quoted reason, a blank
  # line, then a valid row, then the one with no reason.
  expect_error(
    creel_connect_from_yaml(corrections_profile(make_test_csv(), c(
      ',counts,2024-06-01,bank_anglers,12,14,"Recount,',
      'second line"',
      "",
      ",counts,2024-06-02,bank_anglers,8,9,Recount",
      ",counts,2024-06-02,angler_boats,0,1,"
    ))),
    "no reason on line 6"
  )
  # And a multi-line reason on its own is read, not refused.
  conn <- creel_connect_from_yaml(corrections_profile(
    make_test_csv(),
    c(',counts,2024-06-01,bank_anglers,12,14,"Recount,', 'second line"')
  ))
  expect_equal(quiet_fetch(fetch_counts, conn)$bank_anglers, c(14, 8))
})

test_that("numbers match by value and # is not a comment", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  # `12.0` is the stored 12; matched as text it was "the data changed".
  conn <- creel_connect_from_yaml(corrections_profile(
    make_test_csv(), ",counts,2024-06-01,bank_anglers,12.0,14,Recount at Dock#1"
  ))
  counts <- quiet_fetch(fetch_counts, conn)
  expect_equal(counts$bank_anglers, c(14, 8))
  expect_identical(attr(counts, "corrections")$reason, "Recount at Dock#1")
})

test_that("an empty corrections file is refused with a reason", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  yaml_path <- corrections_profile(make_test_csv(), character(0))
  writeLines(character(0), file.path(dirname(yaml_path), "corrections.csv"))
  expect_error(creel_connect_from_yaml(yaml_path), "empty or has no header")
})

test_that("absolute corrections paths are not read relative to the profile", {
  rel <- tidycreel.connect:::.profile_relative
  expect_identical(rel("/srv/c.csv", "/p/x.yml"), "/srv/c.csv")
  expect_identical(rel("C:/c.csv", "/p/x.yml"), "C:/c.csv")
  expect_identical(rel("\\\\server\\share\\c.csv", "/p/x.yml"), "\\\\server\\share\\c.csv")
  expect_identical(rel("c.csv", "/p/x.yml"), file.path("/p", "c.csv"))
})

test_that("a value the column cannot hold is refused, not written as NA", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  conn <- creel_connect_from_yaml(corrections_profile(
    make_test_csv(), ",counts,2024-06-01,bank_anglers,12,twelve,Typo"
  ))
  expect_error(quiet_fetch(fetch_counts, conn), "cannot be read as numeric")
})

# API: corrections are matched on the creel too.
api_corrections_conn <- function(uids, rows, .env = parent.frame()) {
  conn <- tidycreel.connect::creel_connect_api(
    base_url      = "http://test.example.com/api/",
    creel_uids    = uids,
    schema        = tidycreel::creel_schema(survey_type = "instantaneous"),
    uid_param     = "survey_id",
    endpoints     = test_api_endpoints(),
    api_field_map = test_api_field_map()
  )
  path <- withr::local_tempfile(fileext = ".csv", .local_envir = .env)
  writeLines(c(corrections_header, rows), path)
  conn$corrections <- tidycreel.connect:::.read_corrections(path, conn)
  conn
}

mock_counts_by_creel <- function(env = parent.frame()) {
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body    = charToRaw(paste0(
        '[{"SurveyDate":"2016-03-28","ShoreAnglers":12,',
        '"FishingBoats":2,"OtherBoats":1}]'
      ))
    )
  }, env = env)
}

test_that("on a multi-creel API connection a correction changes only its creel", {
  skip_if_not_installed("withr")
  mock_counts_by_creel()
  conn <- api_corrections_conn(
    c("creel-a", "creel-b"),
    c("creel-b,counts,2016-03-28,bank_anglers,12,20,Recount",
      # A creel this connection does not fetch: one file serves them all.
      "creel-z,counts,2016-03-28,bank_anglers,1,2,Other water")
  )
  got <- suppressMessages(fetch_counts(conn))
  expect_equal(got$bank_anglers[got$creel_uid == "creel-a"], 12)
  expect_equal(got$bank_anglers[got$creel_uid == "creel-b"], 20)
  expect_identical(nrow(attr(got, "corrections")), 1L)
})

test_that("a blank creel is refused on a multi-creel API connection", {
  skip_if_not_installed("withr")
  # It would apply to every creel at once.
  expect_error(
    api_corrections_conn(
      c("creel-a", "creel-b"), ",counts,2016-03-28,bank_anglers,12,20,Recount"
    ),
    "blank"
  )
})

test_that("a correction for a table that came back empty stops the fetch", {
  skip_if_not_installed("withr")
  # The empty-response shortcut must not skip the check.
  httr2::local_mocked_responses(function(req) {
    httr2::response(200, headers = "Content-Type: application/json",
                    body = charToRaw("[]"))
  })
  conn <- api_corrections_conn(
    "creel-a", ",counts,2016-03-28,bank_anglers,12,20,Recount"
  )
  expect_error(fetch_counts(conn), class = "creel_error_correction_unmatched")
})
