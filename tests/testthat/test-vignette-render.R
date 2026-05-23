# Smoke test: getting-started.Rmd vignette renders without error

test_that("getting-started.Rmd vignette renders without error", {
  skip_if_not_installed("knitr")
  skip_if_not_installed("rmarkdown")

  vig_path <- normalizePath(
    file.path(dirname(testthat::test_path()), "..", "..", "vignettes", "getting-started.Rmd"),
    mustWork = FALSE
  )
  if (!file.exists(vig_path)) skip("Vignette source not found")

  out_file <- tempfile(fileext = ".html")
  on.exit(unlink(out_file), add = TRUE)

  expect_no_error(
    rmarkdown::render(
      vig_path,
      output_format = "rmarkdown::html_vignette",
      output_file   = out_file,
      envir         = new.env(),
      quiet         = TRUE
    )
  )
})
