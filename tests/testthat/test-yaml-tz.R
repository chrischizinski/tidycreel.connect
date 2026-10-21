# The profile's `tz:` key (#5, tidycreel#407 decision 2026-10-06). Night designs
# need the water's time zone; the profile describes the water, so it carries
# the zone once instead of every script repeating it. What must not happen is
# a session's zone changing under it without a word.

# `paths` comes from make_test_csv() in the test itself, whose frame owns the
# temp files.
tz_yaml <- function(paths, tz = NULL, .env = parent.frame()) {
  yaml_path <- withr::local_tempfile(fileext = ".yml", .local_envir = .env)
  writeLines(c(
    "default:",
    "  backend: csv",
    if (!is.null(tz)) paste0("  tz: ", tz),
    "  files:",
    paste0("    ", names(paths), ": ", unlist(paths)),
    "  schema:",
    "    survey_type: instantaneous"
  ), yaml_path)
  yaml_path
}

test_that("an unset option is set from the profile, with a message", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  withr::local_options(tidycreel.tz = NULL)
  expect_message(
    conn <- creel_connect_from_yaml(
      tz_yaml(make_test_csv(), "America/Chicago")
    ),
    "tidycreel.tz",
    class = "creel_message_tz_option_set"
  )
  expect_identical(getOption("tidycreel.tz"), "America/Chicago")
  expect_identical(conn$tz, "America/Chicago")
})

test_that("a different option already set is kept, with a warning", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  # Set on purpose, perhaps by another water's profile: replacing it would move
  # that water's night designs into this zone.
  withr::local_options(tidycreel.tz = "America/Denver")
  expect_warning(
    conn <- creel_connect_from_yaml(
      tz_yaml(make_test_csv(), "America/Chicago")
    ),
    "America/Denver",
    class = "creel_warning_tz_option_differs"
  )
  expect_identical(getOption("tidycreel.tz"), "America/Denver")
  # The profile's zone is still on the connection, for an explicit tz =.
  expect_identical(conn$tz, "America/Chicago")
})

test_that("the same option already set says nothing", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  # A second profile load in a session must not repeat the message.
  withr::local_options(tidycreel.tz = "America/Chicago")
  expect_no_condition(
    creel_connect_from_yaml(tz_yaml(make_test_csv(), "America/Chicago")),
    class = "creel_message_tz_option_set"
  )
  expect_no_warning(
    creel_connect_from_yaml(tz_yaml(make_test_csv(), "America/Chicago"))
  )
})

test_that("no tz key leaves the option and the connection alone", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  withr::local_options(tidycreel.tz = NULL)
  conn <- creel_connect_from_yaml(tz_yaml(make_test_csv()))
  expect_null(getOption("tidycreel.tz"))
  expect_null(conn$tz)
})

test_that("a zone OlsonNames() does not know aborts before any option is set", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  # A typo caught here, not at the first night design. And it must not leave
  # the bad value behind as the session's zone.
  withr::local_options(tidycreel.tz = NULL)
  expect_error(
    creel_connect_from_yaml(tz_yaml(make_test_csv(), "America/Chicgo")),
    "OlsonNames"
  )
  expect_null(getOption("tidycreel.tz"))
  expect_error(
    creel_connect_from_yaml(tz_yaml(make_test_csv(), "[America/Chicago, UTC]")),
    "OlsonNames"
  )
})

test_that("a profile that fails to connect leaves the option unset", {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  withr::local_options(tidycreel.tz = NULL)
  yaml_path <- tz_yaml(make_test_csv(), "America/Chicago")
  txt <- readLines(yaml_path)
  txt <- sub("survey_type: instantaneous", "survey_type: not_a_type", txt)
  writeLines(txt, yaml_path)
  expect_error(creel_connect_from_yaml(yaml_path), "survey_type")
  expect_null(getOption("tidycreel.tz"))
})
