# tidycreel.connect: ODBC driver diagnostic
# Phase 67: CONNECT-06

#' Check available ODBC drivers
#'
#' @description
#' `creel_check_driver()` lists all ODBC drivers registered on the current
#' system and reports whether a SQL Server-compatible driver is present.
#' This is a diagnostic function intended for setup verification — it does not
#' create a connection.
#'
#' Requires the `odbc` package and an OS-level ODBC driver manager
#' (unixODBC on macOS/Linux, or the Windows ODBC Data Source Administrator).
#'
#' @return `invisible(NULL)` — called for side-effect cli output only.
#' @export
#' @examples
#' \dontrun{
#' creel_check_driver()
#' }
creel_check_driver <- function() {
  if (!requireNamespace("odbc", quietly = TRUE)) {
    cli::cli_abort(c(
      "Package {.pkg odbc} is required to check ODBC drivers.",
      "i" = "Install it with {.code install.packages('odbc')}.",
      "i" = "You will also need an OS-level ODBC driver manager:",
      "i" = "  Windows: built-in (ODBC Data Source Administrator)",
      "i" = "  macOS:   {.code brew install unixodbc}",
      "i" = "  Linux:   {.code sudo apt-get install unixodbc-dev}"
    ))
  }

  # Wrap odbcListDrivers() — OS-level ODBC manager may be absent (Pitfall 3)
  drivers_df <- tryCatch(
    odbc::odbcListDrivers(),
    error = function(e) {
      cli::cli_warn(c(
        "Could not list ODBC drivers: {conditionMessage(e)}",
        "i" = "Ensure an ODBC driver manager is installed:",
        "i" = "  macOS:  {.code brew install unixodbc}",
        "i" = "  Linux:  {.code sudo apt-get install unixodbc-dev}",
        "i" = "  Windows: ODBC manager is built-in."
      ))
      NULL
    }
  )

  if (is.null(drivers_df)) {
    return(invisible(NULL))
  }

  driver_names <- unique(drivers_df$name)

  cli::cli_h2("Available ODBC drivers:")
  if (length(driver_names) == 0L) {
    cli::cli_inform("i" = "No ODBC drivers found.")
  } else {
    cli::cli_bullets(stats::setNames(driver_names, rep("*", length(driver_names))))
  }

  ss_drivers <- grep("SQL Server", driver_names, value = TRUE, ignore.case = TRUE)
  if (length(ss_drivers) > 0L) {
    cli::cli_alert_success("SQL Server driver: detected ({ss_drivers[[1]]})")
  } else {
    cli::cli_alert_warning("SQL Server driver: not detected")
    cli::cli_inform(c(
      "i" = "Install ODBC Driver 17 or 18 for SQL Server from Microsoft:",
      "i" = "  {.url https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server}"
    ))
  }

  invisible(NULL)
}
