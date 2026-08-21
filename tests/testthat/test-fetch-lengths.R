# Tests for fetch_harvest_lengths() and fetch_release_lengths() — FETCH-04, FETCH-05, FETCH-06, BACKEND-01

test_that("fetch_harvest_lengths() returns tibble with canonical columns (FETCH-04)", {
  paths <- make_test_csv()
  schema <- make_test_schema()
  conn <- creel_connect(paths, schema)
  result <- fetch_harvest_lengths(conn)
  expect_true(is.data.frame(result))
  expect_true("length_uid" %in% names(result))
  expect_true("interview_uid" %in% names(result))
  expect_true("species" %in% names(result))
  expect_true("length_mm" %in% names(result))
  expect_true("length_type" %in% names(result))
  expect_true(is.character(result$species))
  expect_true(is.numeric(result$length_mm))
})

test_that("fetch_release_lengths() returns tibble with canonical columns (FETCH-05)", {
  paths <- make_test_csv()
  schema <- make_test_schema()
  conn <- creel_connect(paths, schema)
  result <- fetch_release_lengths(conn)
  expect_true(is.data.frame(result))
  expect_true("length_uid" %in% names(result))
  expect_true("interview_uid" %in% names(result))
  expect_true("species" %in% names(result))
  expect_true("length_mm" %in% names(result))
  expect_true("length_type" %in% names(result))
})

test_that("fetch_harvest_lengths() coerces numeric species codes to character (BACKEND-01)", {
  paths <- make_test_csv_numeric_species()
  schema <- make_test_schema()
  conn <- creel_connect(paths, schema)
  result <- fetch_harvest_lengths(conn)
  expect_true(is.character(result$species))
})

test_that("fetch_*_lengths() aborts with clear error when required column is missing (FETCH-06)", {
  df_bad <- data.frame(
    length_uid = 1L,
    interview_uid = 1L,
    species = "walleye",
    length_type = "harvest",
    stringsAsFactors = FALSE
  )
  # length_mm missing
  expect_error(
    tidycreel.connect:::validate_fetch_harvest_lengths(df_bad),
    "length_mm"
  )
})

# --- creel_connection_api tests (API-04) ---

test_that("fetch_harvest_lengths.creel_connection_api() returns canonical columns (API-04)", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body    = charToRaw('[{"InterviewID":"A1","SpeciesCode":"86","LengthMM":350}]')
    )
  })
  conn   <- make_api_conn()
  result <- fetch_harvest_lengths(conn)
  expect_true(is.data.frame(result))
  expect_equal(
    sort(names(result)),
    sort(c("length_uid", "interview_uid", "species", "length_mm", "length_type"))
  )
  expect_equal(result$interview_uid, "A1")
  expect_true(is.character(result$species))
  expect_true(is.numeric(result$length_mm))
  expect_equal(result$length_type, "harvest")
  expect_true(!is.na(result$length_uid))
})

test_that("fetch_harvest_lengths.creel_connection_api() handles empty API response (API-04)", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(200, headers = "Content-Type: application/json", body = charToRaw("[]"))
  })
  conn   <- make_api_conn()
  result <- fetch_harvest_lengths(conn)
  expect_equal(nrow(result), 0L)
  expect_true("length_uid" %in% names(result))
  expect_true("interview_uid" %in% names(result))
  expect_true("length_type" %in% names(result))
})

# --- creel_connection_api tests (API-05) ---

test_that("fetch_release_lengths.creel_connection_api() returns canonical columns (API-05)", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200,
      headers = "Content-Type: application/json",
      body    = charToRaw('[{"InterviewID":"A1","SpeciesCode":"86","LengthMM":300,"FishCount":1}]')
    )
  })
  conn   <- make_api_conn()
  result <- fetch_release_lengths(conn)
  expect_true(is.data.frame(result))
  expect_equal(
    sort(names(result)),
    sort(c("length_uid", "interview_uid", "species", "length_mm", "length_type"))
  )
  expect_equal(result$interview_uid, "A1")
  expect_true(is.character(result$species))
  expect_true(is.numeric(result$length_mm))
  expect_equal(result$length_type, "release")
})

test_that("fetch_release_lengths.creel_connection_api() handles empty API response (API-05)", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(200, headers = "Content-Type: application/json", body = charToRaw("[]"))
  })
  conn   <- make_api_conn()
  result <- fetch_release_lengths(conn)
  expect_equal(nrow(result), 0L)
  expect_true("length_uid" %in% names(result))
  expect_true("length_type" %in% names(result))
  expect_equal(character(0), result$length_type)
})
