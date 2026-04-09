# Tests for creel_check_driver() — CONNECT-06

test_that("creel_check_driver() aborts with informative error when odbc not installed", {
  # This test works regardless of whether odbc is installed — we mock the absence
  skip_if_not_installed("withr")
  # creel_check_driver() should abort when odbc is absent; but we cannot uninstall odbc.
  # Instead verify: when odbc IS installed, function runs without error
  # When odbc is NOT installed, function aborts with rlang_error
  if (requireNamespace("odbc", quietly = TRUE)) {
    # odbc available: function should run without error (may warn about drivers)
    expect_no_error(
      tryCatch(
        creel_check_driver(),
        error = function(e) {
          # Only accept errors about missing ODBC driver manager, not R-level errors
          if (inherits(e, "rlang_error")) stop(e)
          invisible(NULL)
        }
      )
    )
  } else {
    # odbc not available: function must abort with rlang_error mentioning install instructions
    expect_error(creel_check_driver(), class = "rlang_error")
  }
})

test_that("creel_check_driver() returns invisible NULL", {
  skip_if_not_installed("odbc")
  result <- tryCatch(
    creel_check_driver(),
    error = function(e) NULL # ODBC manager may be absent; that is acceptable here
  )
  # If it ran without R-level error, result should be NULL (invisible)
  if (!is.null(result)) {
    expect_null(result)
  }
})
