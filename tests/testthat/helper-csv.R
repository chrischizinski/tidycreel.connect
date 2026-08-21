# Helper: write temporary CSV fixtures for CSV backend tests
# Returns a named list of file paths (interviews, counts, catch, harvest_lengths, release_lengths)

make_test_schema <- function() {
  tidycreel::creel_schema(
    survey_type       = "instantaneous",
    interview_uid_col = "interview_uid",
    date_col          = "date",
    catch_col         = "catch_count",
    effort_col        = "effort_hours",
    trip_status_col   = "trip_status",
    bank_anglers_col  = "bank_anglers",
    angler_boats_col  = "angler_boats",
    non_ang_boats_col = "non_ang_boats",
    catch_uid_col     = "catch_uid",
    species_col       = "species",
    catch_count_col   = "catch_count",
    catch_type_col    = "catch_type",
    length_uid_col    = "length_uid",
    length_mm_col     = "length_mm",
    length_type_col   = "length_type"
  )
}

make_test_csv <- function() {
  dir <- withr::local_tempdir(.local_envir = parent.frame())

  interviews <- data.frame(
    interview_uid = 1L:2L,
    date = as.Date(c("2024-06-01", "2024-06-02")),
    catch_count = c(3L, 0L),
    effort_hours = c(2.5, 1.0),
    trip_status = c("complete", "incomplete"),
    stringsAsFactors = FALSE
  )
  counts <- data.frame(
    date = as.Date(c("2024-06-01", "2024-06-02")),
    bank_anglers  = c(12L, 8L),
    angler_boats  = c(0L, 0L),
    non_ang_boats = c(0L, 0L),
    stringsAsFactors = FALSE
  )
  catch <- data.frame(
    catch_uid = 1L:2L,
    interview_uid = c(1L, 1L),
    species = c("walleye", "walleye"),
    catch_count = c(2L, 1L),
    catch_type = c("harvest", "release"),
    stringsAsFactors = FALSE
  )
  harvest_lengths <- data.frame(
    length_uid = 1L,
    interview_uid = 1L,
    species = "walleye",
    length_mm = 450.0,
    length_type = "harvest",
    stringsAsFactors = FALSE
  )
  release_lengths <- data.frame(
    length_uid = 2L,
    interview_uid = 1L,
    species = "walleye",
    length_mm = 380.5,
    length_type = "release",
    stringsAsFactors = FALSE
  )

  paths <- list(
    interviews       = file.path(dir, "interviews.csv"),
    counts           = file.path(dir, "counts.csv"),
    catch            = file.path(dir, "catch.csv"),
    harvest_lengths  = file.path(dir, "harvest_lengths.csv"),
    release_lengths  = file.path(dir, "release_lengths.csv")
  )

  utils::write.csv(interviews, paths$interviews, row.names = FALSE)
  utils::write.csv(counts, paths$counts, row.names = FALSE)
  utils::write.csv(catch, paths$catch, row.names = FALSE)
  utils::write.csv(harvest_lengths, paths$harvest_lengths, row.names = FALSE)
  utils::write.csv(release_lengths, paths$release_lengths, row.names = FALSE)

  paths
}

make_test_csv_bom <- function() {
  dir <- withr::local_tempdir(.local_envir = parent.frame())

  interviews <- data.frame(
    interview_uid = 1L:2L,
    date = as.Date(c("2024-06-01", "2024-06-02")),
    catch_count = c(3L, 0L),
    effort_hours = c(2.5, 1.0),
    trip_status = c("complete", "incomplete"),
    stringsAsFactors = FALSE
  )
  counts <- data.frame(
    date = as.Date(c("2024-06-01", "2024-06-02")),
    bank_anglers  = c(12L, 8L),
    angler_boats  = c(0L, 0L),
    non_ang_boats = c(0L, 0L),
    stringsAsFactors = FALSE
  )
  catch <- data.frame(
    catch_uid = 1L:2L,
    interview_uid = c(1L, 1L),
    species = c("walleye", "walleye"),
    catch_count = c(2L, 1L),
    catch_type = c("harvest", "release"),
    stringsAsFactors = FALSE
  )
  harvest_lengths <- data.frame(
    length_uid = 1L,
    interview_uid = 1L,
    species = "walleye",
    length_mm = 450.0,
    length_type = "harvest",
    stringsAsFactors = FALSE
  )
  release_lengths <- data.frame(
    length_uid = 2L,
    interview_uid = 1L,
    species = "walleye",
    length_mm = 380.5,
    length_type = "release",
    stringsAsFactors = FALSE
  )

  paths <- list(
    interviews       = file.path(dir, "interviews.csv"),
    counts           = file.path(dir, "counts.csv"),
    catch            = file.path(dir, "catch.csv"),
    harvest_lengths  = file.path(dir, "harvest_lengths.csv"),
    release_lengths  = file.path(dir, "release_lengths.csv")
  )

  # Write interviews with UTF-8 BOM to simulate Excel export
  writeBin(
    c(as.raw(c(0xEF, 0xBB, 0xBF)), charToRaw(readr::format_csv(interviews))),
    paths$interviews
  )
  utils::write.csv(counts, paths$counts, row.names = FALSE)
  utils::write.csv(catch, paths$catch, row.names = FALSE)
  utils::write.csv(harvest_lengths, paths$harvest_lengths, row.names = FALSE)
  utils::write.csv(release_lengths, paths$release_lengths, row.names = FALSE)

  paths
}

make_test_csv_numeric_species <- function() {
  dir <- withr::local_tempdir(.local_envir = parent.frame())

  interviews <- data.frame(
    interview_uid = 1L:2L,
    date = as.Date(c("2024-06-01", "2024-06-02")),
    catch_count = c(3L, 0L),
    effort_hours = c(2.5, 1.0),
    trip_status = c("complete", "incomplete"),
    stringsAsFactors = FALSE
  )
  counts <- data.frame(
    date = as.Date(c("2024-06-01", "2024-06-02")),
    bank_anglers  = c(12L, 8L),
    angler_boats  = c(0L, 0L),
    non_ang_boats = c(0L, 0L),
    stringsAsFactors = FALSE
  )
  # species column uses integer codes, as many source databases export them
  catch <- data.frame(
    catch_uid = 1L:2L,
    interview_uid = c(1L, 1L),
    species = c(1L, 2L),
    catch_count = c(2L, 1L),
    catch_type = c("harvest", "release"),
    stringsAsFactors = FALSE
  )
  harvest_lengths <- data.frame(
    length_uid = 1L,
    interview_uid = 1L,
    species = 1L,
    length_mm = 450.0,
    length_type = "harvest",
    stringsAsFactors = FALSE
  )
  release_lengths <- data.frame(
    length_uid = 2L,
    interview_uid = 1L,
    species = 1L,
    length_mm = 380.5,
    length_type = "release",
    stringsAsFactors = FALSE
  )

  paths <- list(
    interviews       = file.path(dir, "interviews.csv"),
    counts           = file.path(dir, "counts.csv"),
    catch            = file.path(dir, "catch.csv"),
    harvest_lengths  = file.path(dir, "harvest_lengths.csv"),
    release_lengths  = file.path(dir, "release_lengths.csv")
  )

  utils::write.csv(interviews, paths$interviews, row.names = FALSE)
  utils::write.csv(counts, paths$counts, row.names = FALSE)
  utils::write.csv(catch, paths$catch, row.names = FALSE)
  utils::write.csv(harvest_lengths, paths$harvest_lengths, row.names = FALSE)
  utils::write.csv(release_lengths, paths$release_lengths, row.names = FALSE)

  paths
}
