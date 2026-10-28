# The SQL Server profiles the README and vignette show actually load, and
# fetch (#36).
#
# Those examples are `eval = FALSE`, so nothing ran them, and they drifted: they
# documented an `auth_type:` key no code reads, and `*_col` keys under
# `schema:` that the profile route ignores (it reads a `columns:` block), so a
# user who copied the vignette got a connection with none of its columns
# mapped. Each documented profile is extracted here and loaded through the real
# route, with DBI::dbConnect() mocked, as in test-sqlserver-transport.R.
#
# The source files are read from the repository, so this runs under
# devtools::test() and skips in R CMD check, where they are not beside the
# installed tests.

doc_sqlserver_profiles <- function(path) {
  lines <- readLines(path, warn = FALSE)
  open  <- which(lines == "```yaml")
  close <- which(lines == "```")
  blocks <- lapply(open, function(i) {
    j <- close[close > i][1]
    lines[(i + 1L):(j - 1L)]
  })
  # Only complete profiles whose default block is SQL Server; the
  # multi-environment sketch elides its keys with `# ...`.
  Filter(function(b) {
    any(grepl("^  backend: +sqlserver", b)) && any(grepl("^default:", b)) &&
      !any(grepl("^\\s*# \\.\\.\\.", b))
  }, blocks)
}

# One plausible value per canonical column, for a row of a seeded table.
doc_values <- list(
  interview_uid = "1", date = "2024-06-01", effort = 2.5, catch = 1,
  trip_status = "complete", bank_anglers = 3, angler_boats = 1,
  non_ang_boats = 0, count_time = "08:00"
)
doc_interview_keys <- c("interview_uid", "date", "effort", "catch", "trip_status")
doc_count_keys <- c("date", "count_time", "bank_anglers", "angler_boats",
                    "non_ang_boats")

# A one-row table holding the profile's own column names for these keys.
doc_table <- function(columns, keys) {
  keys <- intersect(keys, names(columns))
  stats::setNames(
    as.data.frame(doc_values[keys], stringsAsFactors = FALSE),
    unlist(columns[keys], use.names = FALSE)
  )
}

# Every top-level key the SQL Server profile route reads. A documented key
# outside this set is one the code silently ignores -- `auth_type` was.
sqlserver_profile_keys <- c(
  "backend", "server", "database", "username", "password",
  "driver", "encrypt", "trust_server_certificate",
  "schema", "tz", "corrections", "cleanup"
)

for (doc in c("README.md", file.path("vignettes", "getting-started.Rmd"))) {
  test_that(paste("every SQL Server profile in", doc, "loads and maps its columns"), {
    path <- test_path("..", "..", doc)
    skip_if_not(file.exists(path), paste(doc, "is not beside the tests"))
    skip_if_not_installed("config")
    skip_if_not_installed("withr")
    skip_if_not_installed("odbc")
    skip_if_not_installed("duckdb")
    skip_if_not_installed("yaml")

    profiles <- doc_sqlserver_profiles(path)
    # Guards the extractor: a reformatted doc must not make this vacuous.
    expect_gte(length(profiles), 1L)

    withr::local_envvar(CREEL_USER = "reader", CREEL_PASS = "not-a-secret")
    real_connect <- DBI::dbConnect
    seed <- NULL
    local_mocked_bindings(
      dbConnect = function(drv, ...) {
        con <- real_connect(duckdb::duckdb())
        seed(con)
        con
      },
      .package = "DBI"
    )

    for (p in profiles) {
      yml <- withr::local_tempfile(fileext = ".yml")
      writeLines(p, yml)

      raw <- yaml::read_yaml(yml, handlers = list(expr = function(x) x))
      sch <- raw[["default"]][["schema"]]
      # The database holds the tables the profile names, with the column
      # names it maps, so a fetch exercises the documented mapping itself.
      seed <- function(con) {
        DBI::dbWriteTable(con, sch[["interviews_table"]],
                          doc_table(sch[["columns"]], doc_interview_keys))
        DBI::dbWriteTable(con, sch[["counts_table"]],
                          doc_table(sch[["columns"]], doc_count_keys))
      }
      expect_setequal(
        setdiff(names(raw[["default"]]), sqlserver_profile_keys),
        character()
      )

      conn <- creel_connect_from_yaml(yml)
      on.exit(DBI::dbDisconnect(conn$con, shutdown = TRUE), add = TRUE)
      # The columns the profile names reached the schema: with `*_col` keys
      # under `schema:` this was NULL.
      cols <- raw[["default"]][["schema"]][["columns"]]
      expect_false(is.null(cols))
      for (k in names(cols)) {
        expect_identical(conn$schema[[paste0(k, "_col")]], cols[[k]])
      }
      # And a fetch can use them. A key that reaches the schema but that no
      # loader reads (`count:` did) passes the check above and fails here.
      iv <- suppressMessages(fetch_interviews(conn))
      expect_true(all(c("interview_uid", "date", "effort") %in% names(iv)))
      ct <- suppressMessages(fetch_counts(conn))
      expect_true("bank_anglers" %in% names(ct))
    }
  })
}
