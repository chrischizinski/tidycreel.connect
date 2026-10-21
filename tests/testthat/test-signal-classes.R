# Every warning and note has a class, and ?connect_warnings lists exactly those
# classes, as tidycreel's do (GH #496). A class is what lets a caller handle one
# signal for one call instead of suppressMessages() on everything, which also
# hides the warnings that mean the fetched data are not what the source holds.

# Each cli_warn() / connect_inform() call in the namespace, with the character
# vector its `class` argument evaluates to (NULL when it has none), and each
# bare cli_inform() call, which would raise a note no class can reach.
signal_calls <- function() {
  ns <- asNamespace("tidycreel.connect")
  found <- list()
  walk <- function(x, where) {
    if (is.call(x)) {
      head <- x[[1]]
      is_warn <- identical(head, quote(cli_warn)) || identical(head, quote(cli::cli_warn))
      is_note <- identical(head, quote(connect_inform))
      is_bare <- identical(head, quote(cli_inform)) || identical(head, quote(cli::cli_inform))
      if (is_warn || is_note || is_bare) {
        cls <- if ("class" %in% names(x)) eval(x[["class"]], baseenv()) else NULL
        kind <- if (is_warn) "warning" else if (is_note) "message" else "bare"
        found[[length(found) + 1]] <<- list(where = where, class = cls, kind = kind)
      }
      for (el in as.list(x)[-1]) if (!missing(el)) walk(el, where)
    }
  }
  # connect_inform() raises its caller's class; it has none of its own.
  for (nm in setdiff(ls(ns, all.names = TRUE), "connect_inform")) {
    f <- get(nm, envir = ns)
    if (is.function(f) && !is.primitive(f)) walk(body(f), nm)
  }
  found
}

test_that("every warning and note has its own class and its family's parent", {
  calls <- signal_calls()
  expect_gt(length(calls), 8)
  for (cl in calls) {
    if (identical(cl$kind, "bare")) {
      # creel_check_driver() is a report: its notes are the output asked for,
      # not signals raised along the way.
      expect_identical(cl$where, "creel_check_driver")
      next
    }
    # connect_inform() adds the parent itself.
    cls <- if (identical(cl$kind, "message")) c(cl$class, "creel_message") else cl$class
    family <- paste0("creel_", cl$kind)
    own <- grep(paste0("^", family, "_"), cls, value = TRUE)
    expect_true(
      family %in% cls && length(own) == 1,
      info = paste0(cl$where, "(): class = ", paste(cls, collapse = ", "))
    )
  }
})

test_that("?connect_warnings and the tier registry list exactly the classes raised", {
  raised <- unique(unlist(lapply(signal_calls(), function(cl) {
    grep("^creel_(warning|message)_", cl$class, value = TRUE)
  })))
  expect_setequal(names(tidycreel.connect:::connect_signal_tiers), raised)

  src <- test_path("..", "..", "man", "connect_warnings.Rd")
  rd <- if (file.exists(src)) tools::parse_Rd(src) else tools::Rd_db("tidycreel.connect")[["connect_warnings.Rd"]]
  txt <- paste(as.character(rd), collapse = "")
  listed <- unique(regmatches(txt, gregexpr("creel_(warning|message)_[a-z_]+", txt))[[1]])
  expect_setequal(listed, raised)
})

# A source with one column nothing maps, so every interviews fetch drops it.
dropping_conn <- function(paths, extra = "weather") {
  iv <- utils::read.csv(paths$interviews)
  iv[[extra]] <- "x"
  utils::write.csv(iv, paths$interviews, row.names = FALSE)
  creel_connect(paths, make_test_schema())
}

dropped_notes <- function(expr) {
  n <- 0L
  withCallingHandlers(
    expr,
    creel_message_columns_dropped = function(m) {
      n <<- n + 1L
      invokeRestart("muffleMessage")
    }
  )
  n
}

test_that("the dropped-columns note prints once per connection, not on every fetch", {
  skip_if_not_installed("withr")
  # The note describes the source, which is the same on every fetch. Printed
  # on every table of every fetch it buried the warnings that matter (#1).
  conn <- dropping_conn(make_test_csv())
  expect_identical(dropped_notes(fetch_interviews(conn)), 1L)
  expect_identical(dropped_notes(fetch_interviews(conn)), 0L)
  # A copy is the same connection, and shares what it has said.
  conn2 <- conn
  expect_identical(dropped_notes(fetch_interviews(conn2)), 0L)
})

test_that("a new connection, or a source that drops something else, prints again", {
  skip_if_not_installed("withr")
  expect_identical(dropped_notes(fetch_interviews(dropping_conn(make_test_csv()))), 1L)
  expect_identical(dropped_notes(fetch_interviews(dropping_conn(make_test_csv()))), 1L)

  # Same connection, different shape: the new column is news.
  conn <- dropping_conn(make_test_csv())
  dropped_notes(fetch_interviews(conn))
  iv <- utils::read.csv(conn$con$interviews)
  iv$wind <- "calm"
  utils::write.csv(iv, conn$con$interviews, row.names = FALSE)
  expect_identical(dropped_notes(fetch_interviews(conn)), 1L)
})

test_that("the first print says repeats are not shown", {
  skip_if_not_installed("withr")
  conn <- dropping_conn(make_test_csv())
  msg <- paste(utils::capture.output(fetch_interviews(conn), type = "message"), collapse = " ")
  expect_match(msg, "weather")
  expect_match(msg, "Shown once per connection")
})

test_that("a classed note can be handled alone, leaving the warnings", {
  skip_if_not_installed("withr")
  # Muffling the note must not hide a coercion warning raised by the same
  # fetch: that is what suppressMessages()-style silencing gets wrong.
  conn <- dropping_conn(make_test_csv())
  iv <- utils::read.csv(conn$con$interviews)
  iv$date[[2]] <- "not a date"
  utils::write.csv(iv, conn$con$interviews, row.names = FALSE)
  expect_warning(
    withCallingHandlers(
      try(fetch_interviews(conn), silent = TRUE),
      creel_message_columns_dropped = function(m) invokeRestart("muffleMessage")
    ),
    class = "creel_warning_dates_coerced_na"
  )
})

test_that("a wide source's note does not abort the fetch", {
  # The once-per-connection key holds every dropped column name; R refuses a
  # binding name over 10,000 bytes, so storing the key as a name turned an
  # informational note into an error on a wide table.
  conn <- list(notes = new.env(parent = emptyenv()))
  key <- c("interviews", sprintf("column_%05d_with_a_long_name", 1:500))
  note <- function() {
    tidycreel.connect:::connect_inform(
      "x", class = "creel_message_columns_dropped", conn = conn, key = key
    )
  }
  expect_message(note(), class = "creel_message_columns_dropped")
  expect_no_message(note())
})
