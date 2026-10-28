# The SQL Server profiles the README and vignette show actually load (#36).
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
    local_mocked_bindings(
      dbConnect = function(drv, ...) real_connect(duckdb::duckdb()),
      .package = "DBI"
    )

    for (p in profiles) {
      yml <- withr::local_tempfile(fileext = ".yml")
      writeLines(p, yml)

      raw <- yaml::read_yaml(yml, handlers = list(expr = function(x) x))
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
    }
  })
}
