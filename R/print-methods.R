# tidycreel.connect: S3 print methods for creel_connection
# Phase 67: CONNECT-05

#' Format a creel_connection for printing
#'
#' @param x A `creel_connection` object.
#' @param ... Unused; for S3 method consistency.
#' @return A character vector of formatted lines (via `cli_format_method()`).
#' @export
format.creel_connection <- function(x, ...) {
  # For DBI backend, re-check validity dynamically
  status_str <- if (x$backend == "csv") { # nolint: object_usage_linter
    x$status
  } else {
    if (DBI::dbIsValid(x$con)) "open" else "closed"
  }

  cli::cli_format_method({
    cli::cli_text("<creel_connection: {x$backend}>")
    cli::cli_text("Status:  {status_str}")

    if (x$backend == "csv") {
      cli::cli_text("Backend: CSV")
      path_names <- names(x$con)
      for (nm in path_names) {
        padded <- formatC(nm, width = max(nchar(path_names)), flag = "-") # nolint: object_usage_linter
        cli::cli_text("  {padded} {cli::symbol$arrow_right} {x$con[[nm]]}")
      }
    } else {
      cli::cli_text("Backend: DBI")
    }

    # Delegate schema summary to format.creel_schema()
    schema_lines <- format(x$schema)
    cli::cli_text("Schema:  {schema_lines[1]}")
    if (length(schema_lines) > 1L) {
      for (ln in schema_lines[-1]) {
        cli::cli_text("{ln}")
      }
    }
  })
}

#' Print a creel_connection
#'
#' @param x A `creel_connection` object.
#' @param ... Passed to `format.creel_connection()`.
#' @return `x` invisibly.
#' @export
print.creel_connection <- function(x, ...) {
  cat(format(x, ...), sep = "\n")
  invisible(x)
}
