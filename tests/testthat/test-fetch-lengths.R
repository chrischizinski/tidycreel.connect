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
