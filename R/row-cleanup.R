# Row cleanup a profile asks for (GH #27).
#
# Some sources serve rows that are artifacts of how they store data, not
# records: a long-format interview table repeats each interview once per
# questionnaire answer, and a source may write a row for a sampled date on
# which nothing was recorded. Since #1 the fetch warns about the first and
# returns both, so every analysis wrote the same few lines to remove them. The
# rows are the same for every creel from that source, so the profile names the
# cleanup once and the fetch applies it, counting what it removed.
#
# Off unless the profile turns it on: a step that removes rows must be asked
# for. Only rows that carry nothing are dropped, and only rows identical in
# every fetched column are collapsed. A row that carries data without an
# interview_uid, or an interview whose rows still differ, is refused for the
# user to resolve rather than dropped or picked between.

# The steps each table accepts, the profile's vocabulary.
.cleanup_steps <- function() {
  list(
    interviews = c("drop_placeholders", "collapse_repeats"),
    counts     = "drop_placeholders"
  )
}

# Internal: is one step turned on for one table?
.cleanup_on <- function(conn, table, step) {
  isTRUE(conn[["cleanup"]][[table]][[step]])
}

# Internal: check a profile's `cleanup:` block. Unknown tables or steps abort,
# so a misspelt step cannot leave the rows in while looking switched on.
.validate_cleanup <- function(block, path) {
  steps <- .cleanup_steps()
  if (!is.list(block) || is.null(names(block)) || any(!nzchar(names(block)))) {
    cli::cli_abort(c(
      "{.field cleanup} must name tables, each with its steps: {.file {path}}",
      "i" = "For example {.code cleanup: {{interviews: {{collapse_repeats: true}}}}}."
    ))
  }
  bad_tables <- setdiff(names(block), names(steps))
  if (length(bad_tables) > 0L) {
    cli::cli_abort(c(
      "Unknown table in {.field cleanup}: {.file {path}}",
      "x" = "Not a table cleanup applies to: {.val {bad_tables}}.",
      "i" = "Cleanup applies to {.val {names(steps)}}."
    ))
  }
  for (table in names(block)) {
    entry <- block[[table]]
    if (!is.list(entry) || is.null(names(entry))) {
      cli::cli_abort(
        "{.field cleanup.{table}} must name its steps: {.file {path}}"
      )
    }
    bad_steps <- setdiff(names(entry), steps[[table]])
    if (length(bad_steps) > 0L) {
      cli::cli_abort(c(
        "Unknown step in {.field cleanup}: {.file {path}}",
        "x" = "Not a step for {table}: {.val {bad_steps}}.",
        "i" = "{table} accepts {.val {steps[[table]]}}."
      ))
    }
    for (step in names(entry)) {
      value <- entry[[step]]
      if (!is.logical(value) || length(value) != 1L || is.na(value)) {
        cli::cli_abort(
          "{.field cleanup.{table}.{step}} must be true or false: {.file {path}}"
        )
      }
    }
  }
  invisible(block)
}

# Internal: the columns that place a row rather than record anything on it.
# A row carrying values only here is a placeholder: the source wrote a row for
# a date (and stratum) with nothing observed on it.
.cleanup_locating_cols <- function(conn) {
  c("creel_uid", "date", names(conn$schema$strata_cols))
}

# Internal: a value that records nothing. A blank string counts: a DBI or API
# source may write a missing id or label as "" rather than null, and treating
# it as a value would keep a placeholder and wave through an orphan row.
.cleanup_blank <- function(x) {
  is.na(x) | (is.character(x) & !nzchar(trimws(x)))
}

# Internal: rows with a value in no column outside the locating ones.
#
# Judged on the fetched columns, not the raw source row. Unmapped source
# columns are gone by now, and they cannot be told apart from the source's own
# bookkeeping (row ids, keys, the date and stratum under their raw names),
# which every placeholder row carries. A source column that holds data the
# analysis needs is mapped, and then it counts here.
.placeholder_rows <- function(df, conn) {
  data_cols <- setdiff(names(df), .cleanup_locating_cols(conn))
  if (length(data_cols) == 0L) {
    return(rep(FALSE, nrow(df)))
  }
  blank <- vapply(df[data_cols], .cleanup_blank, logical(nrow(df)))
  rowSums(!matrix(blank, nrow = nrow(df))) == 0L
}

# Internal: apply a connection's cleanup to one fetched table.
#
# Runs on canonical names and values, after corrections, so a correction is
# applied to every copy before the copies are compared. Records what it did as
# `attr(x, "cleanup")`: rows in = placeholders dropped + repeats collapsed +
# rows kept, so nothing leaves unseen.
#
# `source` and `carried`, when given, are the source rows and the names the
# rename consumed, for .warn_created_duplicates(). It runs here, on the rows
# that survive the placeholder drop, and not at all when repeats are collapsed:
# a warning about rows the caller never receives would send them to fix data
# that is not there.
.apply_cleanup <- function(df, conn, table, source = NULL, carried = character(0)) {
  drop_ph <- .cleanup_on(conn, table, "drop_placeholders")
  collapse <- .cleanup_on(conn, table, "collapse_repeats")
  if (!drop_ph && !collapse) {
    if (!is.null(source)) .warn_created_duplicates(source, df, carried, table)
    return(df)
  }
  kept_attrs <- attributes(df)[setdiff(names(attributes(df)), c("names", "row.names", "class"))]
  rows_in <- nrow(df)
  n_placeholders <- 0L
  n_repeats <- 0L

  if (drop_ph) {
    placeholder <- .placeholder_rows(df, conn)
    if (identical(table, "interviews")) {
      .abort_rows_without_uid(df, placeholder, conn)
    }
    n_placeholders <- sum(placeholder)
    df <- df[!placeholder, , drop = FALSE]
    if (!is.null(source)) source <- source[!placeholder, , drop = FALSE]
  }
  if (!collapse && !is.null(source)) {
    .warn_created_duplicates(source, df, carried, table)
  }
  if (collapse) {
    repeated <- duplicated(df)
    n_repeats <- sum(repeated)
    df <- df[!repeated, , drop = FALSE]
    .abort_conflicting_repeats(df, table)
  }
  rownames(df) <- NULL
  for (nm in names(kept_attrs)) attr(df, nm) <- kept_attrs[[nm]]

  rows_out <- nrow(df)
  counts <- c(
    rows_in = rows_in,
    placeholders_dropped = n_placeholders,
    repeats_collapsed = n_repeats,
    rows_kept = rows_out
  )
  attr(df, "cleanup") <- counts
  steps <- c( # nolint: object_usage_linter
    if (drop_ph) {
      sprintf("dropped %d placeholder row%s", n_placeholders, if (n_placeholders == 1L) "" else "s")
    },
    if (collapse) {
      sprintf("collapsed %d exact repeat%s", n_repeats, if (n_repeats == 1L) "" else "s")
    }
  )
  connect_inform(
    c("i" = "{table}: kept {rows_out} of {rows_in} row{?s}; {paste(steps, collapse = ', ')}, as the profile's {.field cleanup} asks."),
    class = "creel_message_rows_cleaned",
    conn = conn,
    key = c(table, counts)
  )
  df
}

# Internal: an interview row with no interview_uid that still carries data
# cannot be joined to its catch and is not a placeholder, so it is neither kept
# silently nor dropped: the user decides. Column names and a count only; a
# value can be personal (a ZIP code).
.abort_rows_without_uid <- function(df, placeholder, conn) {
  if (!"interview_uid" %in% names(df)) {
    return(invisible(NULL))
  }
  orphan <- .cleanup_blank(df$interview_uid) & !placeholder
  if (!any(orphan)) {
    return(invisible(NULL))
  }
  data_cols <- setdiff(names(df), .cleanup_locating_cols(conn))
  filled <- data_cols[vapply(data_cols, function(col) { # nolint: object_usage_linter
    any(!.cleanup_blank(df[[col]][orphan]))
  }, logical(1L))]
  n_orphan <- sum(orphan) # nolint: object_usage_linter
  cli::cli_abort(c(
    "interviews: {n_orphan} row{?s} ha{?s/ve} no {.field interview_uid} but carr{?ies/y} data.",
    "i" = "The data are in {.field {filled}}.",
    "x" = "{.field drop_placeholders} drops only rows that carry nothing but a date and strata.",
    "i" = "Fix the source or add a correction, or turn {.field drop_placeholders} off to keep them."
  ), class = "creel_error_cleanup_rows_without_uid")
}

# Internal: after exact copies are collapsed, one interview_uid on two rows
# means the rows disagree, and choosing between them would be a guess. Names
# the columns that differ and a count; never the values.
.abort_conflicting_repeats <- function(df, table) {
  if (!"interview_uid" %in% names(df)) {
    return(invisible(NULL))
  }
  key <- df$interview_uid
  if ("creel_uid" %in% names(df)) key <- paste(df$creel_uid, key, sep = "\x1f")
  dup <- !.cleanup_blank(df$interview_uid) & (duplicated(key) | duplicated(key, fromLast = TRUE))
  if (!any(dup)) {
    return(invisible(NULL))
  }
  sub <- df[dup, , drop = FALSE]
  sub_key <- key[dup]
  differs <- names(sub)[vapply(names(sub), function(col) { # nolint: object_usage_linter
    pairs <- unique(data.frame(k = sub_key, v = .comparable(sub[[col]]), stringsAsFactors = FALSE))
    anyDuplicated(pairs$k) > 0L
  }, logical(1L))]
  n_ids <- length(unique(sub_key)) # nolint: object_usage_linter
  cli::cli_abort(c(
    "{table}: {n_ids} interview{?s} still ha{?s/ve} more than one row after exact repeats were collapsed.",
    "i" = "Their rows differ in {.field {differs}}.",
    "x" = "Picking one row would be a guess, and keeping both counts the interview twice.",
    "i" = "Fix the source or add a correction, or map the column that tells the rows apart."
  ), class = "creel_error_cleanup_conflicting_repeats")
}
