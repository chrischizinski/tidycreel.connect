# Documented data corrections (GH #4, part A).
#
# Real data need recorded fixes: a count dated to the wrong shift, a code keyed
# wrong. Done in a script they are invisible to anyone reading the totals. A
# corrections file names each one, with the reason, and the fetch applies it,
# says so, and stops when a correction no longer matches anything -- the data
# changed underneath it and the fix has to be looked at again.

# Tables a correction can name. A correction is keyed on the record's date, and
# only these two tables carry one; catch and lengths are keyed by interview.
.correction_tables <- function() c("interviews", "counts")

.correction_cols <- function() {
  c("creel_uid", "table", "date", "field", "from", "to", "reason")
}

# Internal: read and check a corrections file against the connection it is for.
# Returns the rows that apply to this connection, all columns character.
#
# A blank creel_uid means "this connection's creel" (#4 decision D5): the CSV
# and DBI backends carry no creel label, and a single-UID API connection has
# only one creel to mean. On a multi-UID API connection a blank row would apply
# to every creel at once, so it is refused. Rows naming a creel this connection
# did not ask for are left out: one file can serve every creel an agency runs.
.read_corrections <- function(path, conn) {
  if (!file.exists(path)) {
    cli::cli_abort("The corrections file does not exist: {.file {path}}")
  }
  # A row with more fields than the header -- a reason with an unquoted
  # comma -- would otherwise be read with its first field as a row name and
  # every value shifted one column left.
  n_fields <- utils::count.fields(path, sep = ",", quote = "\"", blank.lines.skip = TRUE)
  if (any(n_fields != n_fields[[1L]])) {
    lines <- which(n_fields != n_fields[[1L]]) # nolint: object_usage_linter
    cli::cli_abort(c(
      "The corrections file has a different number of fields on \\
       {cli::qty(length(lines))}line{?s} {lines}: {.file {path}}",
      "i" = "Quote a value that contains a comma, e.g. {.code \"Recount, field sheet\"}."
    ))
  }
  cx <- utils::read.csv(
    path,
    colClasses = "character", na.strings = character(0),
    strip.white = TRUE, check.names = FALSE
  )
  missing_cols <- setdiff(.correction_cols(), names(cx))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "The corrections file lacks column{?s} {.field {missing_cols}}: {.file {path}}",
      "i" = "Columns: {.field {(.correction_cols())}}."
    ))
  }
  cx <- cx[.correction_cols()]
  row <- seq_len(nrow(cx)) + 1L # the line in the file, after the header

  .refuse_rows <- function(bad, what, hint) {
    if (any(bad)) {
      lines <- row[bad] # nolint: object_usage_linter
      # `what` and `hint` carry cli markup, so they are part of the template
      # rather than values interpolated into it.
      cli::cli_abort(c(
        paste0(what, " on {cli::qty(length(lines))}line{?s} {lines} of {.file {path}}."),
        "i" = hint
      ))
    }
  }
  # A correction with no reason cannot be audited, which is the point of
  # writing it down.
  .refuse_rows(!nzchar(cx$reason), "A correction has no {.field reason}",
               "Every correction states why it was made.")
  .refuse_rows(!nzchar(cx$field) | !nzchar(cx$from) | !nzchar(cx$to),
               "A correction leaves {.field field}, {.field from} or {.field to} blank",
               "Name the column and both values; a blank cannot be matched or written.")
  .refuse_rows(!cx$table %in% .correction_tables(),
               "A correction names a table other than {.val {(.correction_tables())}}",
               "Corrections are keyed on a record's date, which only those tables carry.")
  .refuse_rows(is.na(as.Date(cx$date, format = "%Y-%m-%d")) |
                 !grepl("^\\d{4}-\\d{2}-\\d{2}$", cx$date),
               "A correction's {.field date} is not YYYY-MM-DD",
               "Write the date as, e.g., 2025-06-14.")

  blank <- !nzchar(cx$creel_uid)
  if (identical(conn$backend, "api")) {
    uids <- conn$con$creel_uids
    if (length(uids) > 1L) {
      .refuse_rows(blank, "A correction leaves {.field creel_uid} blank",
                   "This connection fetches several creels; name the one it corrects.")
    }
    cx <- cx[blank | cx$creel_uid %in% uids, , drop = FALSE]
  } else {
    .refuse_rows(!blank, "A correction names a {.field creel_uid}",
                 "This backend carries no creel label to match; leave it blank.")
  }
  row.names(cx) <- NULL
  cx
}

# Internal: apply a connection's corrections for one table, in file order.
# Runs on canonical names and values (after rename and value maps), before
# validation, so a correction is written in tidycreel's terms and its result is
# what gets validated.
.apply_corrections <- function(df, conn, table) {
  cx <- conn[["corrections"]]
  if (is.null(cx)) {
    return(df)
  }
  cx <- cx[cx$table == table, , drop = FALSE]
  if (nrow(cx) == 0L) {
    return(df)
  }
  n_rows <- integer(nrow(cx))
  for (i in seq_len(nrow(cx))) {
    field <- cx$field[[i]]
    if (!field %in% names(df)) {
      cli::cli_abort(c(
        "A correction names {.field {field}}, which the fetched {table} does not have.",
        "i" = "Corrections use tidycreel's column names, after the field map."
      ), class = "creel_error_correction_unmatched")
    }
    hit <- as.character(df$date) == cx$date[[i]] & as.character(df[[field]]) == cx$from[[i]]
    if (nzchar(cx$creel_uid[[i]]) && "creel_uid" %in% names(df)) {
      hit <- hit & df$creel_uid == cx$creel_uid[[i]]
    }
    hit <- hit %in% TRUE
    if (!any(hit)) {
      cli::cli_abort(c(
        "A correction to {table} matched no rows: {.field {field}} {.val {cx$from[[i]]}} on {cx$date[[i]]}.",
        "x" = "The data changed underneath it, so it can no longer be applied as written.",
        "i" = "Check the record, then update or remove the correction."
      ), class = "creel_error_correction_unmatched")
    }
    df[[field]][hit] <- .correction_value(cx$to[[i]], df[[field]], field)
    n_rows[[i]] <- sum(hit)
  }

  applied <- cbind(cx, n_rows = n_rows)
  lines <- sprintf(
    "%s%s: %s %s -> %s on %d row%s (%s)",
    ifelse(nzchar(cx$creel_uid), paste0(cx$creel_uid, " "), ""),
    cx$date, cx$field, cx$from, cx$to, n_rows, ifelse(n_rows == 1L, "", "s"), cx$reason
  )
  # Values come from the file; doubled braces keep cli from reading them as code.
  lines <- gsub("([{}])", "\\1\\1", lines)
  connect_inform(
    c(
      "i" = "{table}: applied {nrow(cx)} correction{?s} from the corrections file.",
      stats::setNames(lines, rep("*", length(lines)))
    ),
    class = "creel_message_corrections_applied",
    conn = conn,
    key = c(table, lines)
  )
  attr(df, "corrections") <- applied
  df
}

# Internal: a correction's `to`, as the column's type. A value the type cannot
# hold aborts rather than writing NA over a record.
.correction_value <- function(to, column, field) {
  out <- if (inherits(column, "Date")) {
    as.Date(to, format = "%Y-%m-%d")
  } else if (is.numeric(column)) {
    suppressWarnings(as.numeric(to))
  } else if (is.logical(column)) {
    as.logical(to)
  } else {
    to
  }
  if (is.na(out)) {
    type <- class(column)[[1L]] # nolint: object_usage_linter
    cli::cli_abort(
      "A correction's {.field to} value {.val {to}} cannot be read as {type} for {.field {field}}."
    )
  }
  out
}
