# tidycreel.connect

<p align="center">
<img src="https://raw.githubusercontent.com/chrischizinski/tidycreel.connect/main/man/figures/logo.png" alt="tidycreel.connect hex sticker" width="200"/>
</p>

<!-- badges: start -->
[![R-CMD-check](https://github.com/chrischizinski/tidycreel.connect/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/chrischizinski/tidycreel.connect/actions/workflows/R-CMD-check.yaml)
[![pkgdown](https://img.shields.io/badge/pkgdown-live-1B4F72)](https://chrischizinski.com/tidycreel.connect/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![Roadmap](https://img.shields.io/badge/Roadmap-tidycreel.connect-6f42c1?logo=github)](https://github.com/users/chrischizinski/projects/3)
[![Report bug](https://img.shields.io/badge/Report%20Bug-d73a4a?logo=github)](https://github.com/chrischizinski/tidycreel.connect/issues/new?labels=bug)
[![Request feature](https://img.shields.io/badge/Request%20Feature-1f6feb?logo=github)](https://github.com/chrischizinski/tidycreel.connect/issues/new?labels=enhancement)
[![GitHub Discussions](https://img.shields.io/github/discussions/chrischizinski/tidycreel.connect?logo=github)](https://github.com/chrischizinski/tidycreel.connect/discussions)
<!-- badges: end -->

**Database and file connections for the
[tidycreel](https://github.com/chrischizinski/tidycreel) creel survey package.**

tidycreel.connect provides a unified connection layer that loads interview,
count, catch, and length data from flat CSV files or a REST API, renames
columns to the canonical names expected by tidycreel, and coerces types
consistently — so the rest of your analysis code doesn't care where the data
came from.

A database backend loads through DBI, so SQL Server via ODBC works, and so
does anything else with a DBI driver. It reads each table by the name the
schema gives it and puts the rows through the same rename, coercion and
validation the CSV backend uses. Survey *discovery* — `list_creels()` and
`search_creels()` — does not apply to a database connection, which addresses
one set of tables rather than a catalogue.

---

## Installation

```r
# install.packages("pak")
# Installs tidycreel from GitHub too, if it is not already installed
pak::pak("chrischizinski/tidycreel.connect")
```

### ODBC prerequisites (SQL Server connections only)

These are needed to open a SQL Server connection. Other DBI drivers (duckdb,
Postgres, SQLite) need no ODBC setup.

You need both the **R `odbc` package** and a **native ODBC driver** for your OS.

```r
install.packages("odbc")
```

Then install the Microsoft ODBC Driver 18 for SQL Server, which a YAML
profile uses by default (Driver 17 works too; see `?creel_connect_from_yaml`):

#### Windows

Download and run the installer from Microsoft:

- [ODBC Driver 18 for SQL Server (Windows)](https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server)
- Or install silently via winget:
  ```
  winget install Microsoft.ODBCDriverForSQLServer
  ```

#### macOS

Install unixODBC and the Microsoft driver via Homebrew:

```bash
# 1. Install unixODBC (ODBC driver manager)
brew install unixodbc

# 2. Add the Microsoft tap
brew tap microsoft/mssql-release https://github.com/Microsoft/homebrew-mssql-release

# 3. Install ODBC Driver 18 for SQL Server
HOMEBREW_ACCEPT_EULA=Y brew install msodbcsql18

# Optional: also install the command-line tools
HOMEBREW_ACCEPT_EULA=Y brew install mssql-tools18
```

Verify the driver is registered:

```r
odbc::odbcListDrivers()
# Should include: ODBC Driver 17 for SQL Server  (or 18)
```

#### Linux (Ubuntu / Debian)

```bash
# 1. Add Microsoft package repository
curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
curl https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/prod.list \
  | sudo tee /etc/apt/sources.list.d/mssql-release.list

# 2. Install ODBC Driver 18
sudo apt-get update
ACCEPT_EULA=Y sudo apt-get install -y msodbcsql18

# 3. Install unixODBC development headers (needed by the R odbc package)
sudo apt-get install -y unixodbc-dev
```

#### Linux (RHEL / CentOS / Fedora)

```bash
sudo curl -o /etc/yum.repos.d/mssql-release.repo \
  https://packages.microsoft.com/config/rhel/8/prod.repo

ACCEPT_EULA=Y sudo dnf install -y msodbcsql18
sudo dnf install -y unixODBC-devel
```

---

## Quick start

### CSV backend

```r
library(tidycreel)
library(tidycreel.connect)

# 1. Connect via YAML config — the profile carries the column mapping
conn <- creel_connect_from_yaml("creel-config.yml")

# 2. Fetch data
interviews      <- fetch_interviews(conn)
counts          <- fetch_counts(conn)
catch_data      <- fetch_catch(conn)
harvest_lengths <- fetch_harvest_lengths(conn)
release_lengths <- fetch_release_lengths(conn)
```

**creel-config.yml** (CSV backend):

```yaml
default:
  backend: csv
  files:
    interviews:      data/interviews.csv
    counts:          data/counts.csv
    catch:           data/catch.csv
    harvest_lengths: data/harvest_lengths.csv
    release_lengths: data/release_lengths.csv
  schema:
    survey_type: instantaneous
    # What your columns are called. Keys are tidycreel's canonical names, with
    # no `_col` suffix; an unmapped column is dropped on the way in.
    columns:
      interview_uid: InterviewID
      date:          SurveyDate
      effort:        EffortHours
      catch:         TotalCatch
      trip_status:   TripStatus
      bank_anglers:  BankAnglers
      angler_boats:  AnglerBoats
      catch_uid:     CatchUID
      species:       SpeciesCode
      catch_count:   CatchCount
      catch_type:    CatchCategory
      length_uid:    LengthUID
      length_mm:     LengthMM
      length_type:   LengthType
```

A full commented template is installed with the package:

```r
system.file("extdata", "csv-profile-example.yml", package = "tidycreel.connect")
```

### SQL Server backend

> The `schema:` block must name the tables as well as the columns:
> `interviews_table`, `counts_table`, `catch_table`, and
> `harvest_lengths_table` / `release_lengths_table` (both falling back to
> `lengths_table` when the source keeps one). A table the schema does not name
> cannot be fetched — there is no canonical table name to fall back on the way
> there is for a column.
>
> `list_creels()` and `search_creels()` do not apply to a database connection
> and say so; use the API backend for a source whose service defines
> discovery.

**creel-config.yml** (SQL Server with password auth):

```yaml
default:
  backend:   sqlserver
  server:    myserver.example.com
  database:  CreelDB
  username:  !expr Sys.getenv("CREEL_USER")
  password:  !expr Sys.getenv("CREEL_PASS")
  # Optional. These are the defaults: Driver 18, encrypted, certificate
  # verified. Turning either protection off warns on every connect.
  # driver: ODBC Driver 18 for SQL Server
  # encrypt: true
  # trust_server_certificate: false
  schema:
    survey_type:      instantaneous
    interviews_table: vwInterviews
    counts_table:     vwCounts
    catch_table:      vwCatch
    lengths_table:    vwLengths
    columns:
      interview_uid: InterviewID
      date:          SurveyDate
      effort:        EffortHours
      catch:         TotalCatch
      trip_status:   TripStatus
      bank_anglers:  BankAnglers
      angler_boats:  AnglerBoats
      catch_uid:     CatchUID
      species:       SpeciesCode
      catch_count:   CatchCount
      catch_type:    CatchCategory
      length_uid:    LengthUID
      length_mm:     LengthMM
      length_type:   LengthType
```

Set credentials before connecting — never store them as plain text:

```r
# In ~/.Renviron (never commit this file):
# CREEL_USER=your_username
# CREEL_PASS=your_password

Sys.setenv(CREEL_USER = "your_username", CREEL_PASS = "your_password")
conn <- creel_connect_from_yaml("creel-config.yml")
```

---

## Authentication

A SQL Server profile connects with a SQL Server login: `username` and
`password`, read with `!expr` from the environment or a keyring, never written
in the file. Windows integrated authentication is not supported by the profile
route; for it, build the connection with `DBI::dbConnect()` and pass it to
`creel_connect()`.

API profiles authenticate with a bearer token or an API key; see
`?creel_connect_api`.

---

## Further reading

- `vignette("getting-started", package = "tidycreel.connect")` — full
  walkthrough of YAML config, schema setup, fetching data, and integrating
  with the tidycreel estimation API
- `vignette("getting-started", package = "tidycreel")` — complete estimation
  pipeline from design through results
