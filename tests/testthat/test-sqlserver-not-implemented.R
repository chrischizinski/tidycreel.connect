# The SQL Server backend is configurable and connectable, but no data loader for
# it exists yet: every fetch_*() method is a stub that aborts. That state was
# undocumented and untested for long enough that DESCRIPTION, the README and the
# getting-started vignette all described it as a working backend (GH #169).
#
# These pin the stubs. If someone implements the loaders, these tests fail and
# say so, which is the prompt to correct the docs in the same change.

sqlserver_conn <- function() {
  structure(
    list(
      backend = "sqlserver",
      con     = NULL,
      schema  = tidycreel::creel_schema(survey_type = "instantaneous"),
      status  = "open"
    ),
    class = c("creel_connection_sqlserver", "creel_connection")
  )
}

test_that("every SQL Server fetch_*() aborts as unimplemented", {
  conn <- sqlserver_conn()
  fetchers <- list(
    fetch_interviews      = fetch_interviews,
    fetch_counts          = fetch_counts,
    fetch_catch           = fetch_catch,
    fetch_harvest_lengths = fetch_harvest_lengths,
    fetch_release_lengths = fetch_release_lengths
  )
  for (nm in names(fetchers)) {
    # The message must name the function, so a user who followed the README's
    # SQL Server section learns which call is missing rather than that
    # "something" is unimplemented.
    expect_error(fetchers[[nm]](conn), "not yet implemented", info = nm)
    expect_error(fetchers[[nm]](conn), nm, fixed = TRUE, info = nm)
  }
})

test_that("SQL Server discovery aborts as not supported", {
  conn <- sqlserver_conn()
  expect_error(list_creels(conn), "not supported")
  expect_error(search_creels(conn, "anything"), "not supported")
})
