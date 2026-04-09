# Tests for fetch_catch() — FETCH-03, FETCH-06, BACKEND-01

test_that("fetch_catch() returns tibble with canonical columns (FETCH-03)", {
  paths <- make_test_csv()
  schema <- make_test_schema()
  conn <- creel_connect(paths, schema)
  result <- fetch_catch(conn)
  expect_true(is.data.frame(result))
  expect_true("catch_uid" %in% names(result))
  expect_true("interview_uid" %in% names(result))
  expect_true("species" %in% names(result))
  expect_true("catch_count" %in% names(result))
  expect_true("catch_type" %in% names(result))
  expect_true(is.character(result$species))
  expect_true(is.numeric(result$catch_count))
})

test_that("fetch_catch() coerces numeric species codes to character (BACKEND-01)", {
  paths <- make_test_csv_numeric_species()
  schema <- make_test_schema()
  conn <- creel_connect(paths, schema)
  result <- fetch_catch(conn)
  expect_true(is.character(result$species))
})

test_that("fetch_catch() aborts with clear error when required column is missing (FETCH-06)", {
  df_bad <- data.frame(
    catch_uid = "A",
    interview_uid = "B",
    catch_count = 1.0,
    catch_type = "harvest",
    stringsAsFactors = FALSE
  )
  # species missing
  expect_error(
    tidycreel.connect:::validate_fetch_catch(df_bad),
    "species"
  )
})
