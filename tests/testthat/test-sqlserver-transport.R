# A SQL Server profile connects encrypted, certificate verified, by default (#31).
#
# Before #31 the profile route hardcoded Driver 17 and named neither `Encrypt`
# nor `TrustServerCertificate`. Driver 17 does not encrypt unless asked, so
# unless the server forced it, the login and every row -- which can include
# personal data -- crossed the network in cleartext. These tests capture the
# arguments handed to DBI::dbConnect(), so no server is needed: what is
# asserted is what the driver is told to do.

sqlserver_profile <- function(extra = character(), envir = parent.frame()) {
  path <- withr::local_tempfile(fileext = ".yml", .local_envir = envir)
  writeLines(c(
    "default:",
    "  backend: sqlserver",
    "  server: db.example.org",
    "  database: CreelDB",
    "  username: creel_reader",
    # A literal only because this is a test: a real profile reads it with
    # !expr Sys.getenv(), and the value doubles as a sentinel below.
    "  password: SENTINEL-PW-31",
    paste0("  ", extra),
    "  schema:",
    "    survey_type: instantaneous",
    "    interviews_table: interviews"
  ), path)
  path
}

skip_if_no_sqlserver_mock <- function() {
  skip_if_not_installed("config")
  skip_if_not_installed("withr")
  skip_if_not_installed("odbc")
  skip_if_not_installed("duckdb")
}

test_that("the default is Driver 18, encrypted, certificate verified", {
  skip_if_no_sqlserver_mock()
  path <- sqlserver_profile()
  real_connect <- DBI::dbConnect
  seen <- new.env()
  local_mocked_bindings(
    dbConnect = function(drv, ...) {
      seen$args <- list(...)
      real_connect(duckdb::duckdb())
    },
    .package = "DBI"
  )
  expect_no_warning(conn <- creel_connect_from_yaml(path))
  on.exit(DBI::dbDisconnect(conn$con, shutdown = TRUE), add = TRUE)

  expect_identical(seen$args$Driver, "ODBC Driver 18 for SQL Server")
  expect_identical(seen$args$Encrypt, "yes")
  expect_identical(seen$args$TrustServerCertificate, "no")
})

test_that("a profile naming Driver 17 still asks it to encrypt", {
  # Driver 17's own default is no encryption, so the guarantee must not come
  # from the driver's default.
  skip_if_no_sqlserver_mock()
  path <- sqlserver_profile("driver: ODBC Driver 17 for SQL Server")
  real_connect <- DBI::dbConnect
  seen <- new.env()
  local_mocked_bindings(
    dbConnect = function(drv, ...) {
      seen$args <- list(...)
      real_connect(duckdb::duckdb())
    },
    .package = "DBI"
  )
  expect_no_warning(conn <- creel_connect_from_yaml(path))
  on.exit(DBI::dbDisconnect(conn$con, shutdown = TRUE), add = TRUE)
  expect_identical(seen$args$Driver, "ODBC Driver 17 for SQL Server")
  expect_identical(seen$args$Encrypt, "yes")
})

test_that("turning a protection off is passed through, and warns", {
  skip_if_no_sqlserver_mock()
  real_connect <- DBI::dbConnect
  seen <- new.env()
  local_mocked_bindings(
    dbConnect = function(drv, ...) {
      seen$args <- list(...)
      real_connect(duckdb::duckdb())
    },
    .package = "DBI"
  )

  expect_warning(
    conn <- creel_connect_from_yaml(sqlserver_profile("encrypt: false")),
    class = "creel_warning_sqlserver_unencrypted"
  )
  DBI::dbDisconnect(conn$con, shutdown = TRUE)
  expect_identical(seen$args$Encrypt, "no")

  expect_warning(
    conn <- creel_connect_from_yaml(
      sqlserver_profile("trust_server_certificate: true")
    ),
    class = "creel_warning_sqlserver_certificate_unverified"
  )
  DBI::dbDisconnect(conn$con, shutdown = TRUE)
  expect_identical(seen$args$Encrypt, "yes")
  expect_identical(seen$args$TrustServerCertificate, "yes")
})

test_that("a longer key cannot reach a transport setting by partial matching", {
  # `cfg$encrypt` partially matches `encryption`, so reading the settings with
  # `$` let an unvalidated key switch encryption off without a warning. The
  # settings are read with `[[` now, and since #40 such a key never gets that
  # far: it is refused by name before anything reads it.
  skip_if_no_sqlserver_mock()
  local_mocked_bindings(
    dbConnect = function(drv, ...) stop("dbConnect must not be reached"),
    .package = "DBI"
  )
  err <- expect_error(
    creel_connect_from_yaml(sqlserver_profile(c("encryption: false", "driverx: Some Driver"))),
    class = "creel_error_profile_unknown_key"
  )
  expect_match(conditionMessage(err), "encryption")
  expect_match(conditionMessage(err), "driverx")
})

test_that("both protections off raise both warnings", {
  skip_if_no_sqlserver_mock()
  real_connect <- DBI::dbConnect
  local_mocked_bindings(
    dbConnect = function(drv, ...) real_connect(duckdb::duckdb()),
    .package = "DBI"
  )
  classes <- character()
  conn <- withCallingHandlers(
    creel_connect_from_yaml(sqlserver_profile(
      c("encrypt: false", "trust_server_certificate: true")
    )),
    creel_warning = function(w) {
      classes <<- c(classes, class(w)[[1]])
      invokeRestart("muffleWarning")
    }
  )
  DBI::dbDisconnect(conn$con, shutdown = TRUE)
  expect_setequal(classes, c(
    "creel_warning_sqlserver_unencrypted",
    "creel_warning_sqlserver_certificate_unverified"
  ))
})

test_that("malformed transport keys abort before any connection is tried", {
  skip_if_no_sqlserver_mock()
  local_mocked_bindings(
    dbConnect = function(drv, ...) stop("dbConnect must not be reached"),
    .package = "DBI"
  )
  expect_error(
    creel_connect_from_yaml(sqlserver_profile('encrypt: "yes"')),
    "encrypt.* must be"
  )
  expect_error(
    creel_connect_from_yaml(sqlserver_profile("trust_server_certificate: 1")),
    "trust_server_certificate.* must be"
  )
  expect_error(
    creel_connect_from_yaml(sqlserver_profile('driver: ""')),
    "driver.* must be one ODBC driver name"
  )
})

test_that("a missing driver is named, with the way out", {
  skip_if_no_sqlserver_mock()
  local_mocked_bindings(
    dbConnect = function(drv, ...) {
      stop("[unixODBC][Driver Manager]Can't open lib 'ODBC Driver 18 for SQL Server'")
    },
    .package = "DBI"
  )
  local_mocked_bindings(
    odbcListDrivers = function(...) {
      data.frame(name = "ODBC Driver 17 for SQL Server", attribute = "Driver")
    },
    .package = "odbc"
  )
  expect_error(
    creel_connect_from_yaml(sqlserver_profile()),
    "Driver 18 for SQL Server.* is not installed"
  )
})

test_that("a driver message quoting the password is withheld whole", {
  # odbc 1.7.0 does not quote it (checked 2026-10-28); this guards the case
  # where some driver or version does.
  skip_if_no_sqlserver_mock()
  local_mocked_bindings(
    dbConnect = function(drv, ...) {
      stop("login failed; connection string PWD=SENTINEL-PW-31;")
    },
    .package = "DBI"
  )
  err <- expect_error(creel_connect_from_yaml(sqlserver_profile()), "withheld")
  expect_no_match(conditionMessage(err), "SENTINEL-PW-31")
})

test_that("a driver message with braces is shown, not interpolated", {
  # Passed as a cli bullet's text, `{...}` in a driver message used to be
  # evaluated as glue.
  skip_if_no_sqlserver_mock()
  local_mocked_bindings(
    dbConnect = function(drv, ...) stop("TCP Provider: error {code 0x2726}"),
    .package = "DBI"
  )
  expect_error(
    creel_connect_from_yaml(sqlserver_profile()),
    "error \\{code 0x2726\\}"
  )
})
