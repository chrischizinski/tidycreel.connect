# Data handling

tidycreel.connect is a connector package. It reads an agency's creel data at
run time, through a connection the user supplies (CSV paths, a DBI database or
a REST API). It stores no survey data of its own.

## Where sensitive data lives

| Data | Location (outside this repo) | Contains PII? | Custodian |
|---|---|---|---|
| Agency creel interviews, counts, catch and lengths | The agency's database or API, reached through `creel_connect()` / `creel_connect_api()` | Possibly (e.g. angler ZIP code, interviewer names) | The agency data steward |
| Shipped fixture: `inst/extdata/synthetic-boat-counts/counts.csv` | In this repo (whitelisted in `.gitignore`) | No: synthetic daily aggregate counts | Package maintainer |

PII never enters this repository. Test fixtures are synthetic, built in test
helpers or written to `tempdir()`, and never copied from an agency extract.

## What analysts receive

- The fetch functions return what the connection is mapped to carry. Map only
  the fields an analysis needs; unmapped columns are dropped.
- Quasi-identifiers such as `zip_code` are summarised (by ZIP or county), not
  reported row by row.
- Small cells are suppressed per agency policy before results leave the secure
  environment.

## Credentials

- Never written in code or in a committed YAML profile. Profiles read them with
  `!expr`, from the OS keyring (`keyring::key_get()`) or the environment
  (`Sys.getenv()`).
- For an API token, prefer a **function** that looks it up at request time,
  e.g. `token: !expr function() keyring::key_get("creel-api")`. A token given
  as a string is held in the connection object: `print()` hides it, but
  `str()`, `dput()`, `saveRDS()`, `save()` and a saved `.RData` workspace all
  write it out (checked 2026-10-28). A function that looks the token up keeps
  it out of all of them. A function that returns a token *variable* does not
  help: made inside another function or `local()`, the variable is saved with
  the function; made at top level, it stays in the workspace and a saved
  `.RData` holds it.
- Never save a connection object to disk, and do not save the workspace on exit
  in a session that holds one. Save the fetched data and reconnect.
- Print methods never show a password or token; keep it that way.
- Use read-only database accounts.
- A credential that appears in a commit, log, or chat transcript is treated as
  compromised and rotated.

## Profiles are code

A YAML profile is evaluated by `config`, which runs every `!expr` value as R
with the user's permissions, credentials and data access. Read a profile you did
not write before loading it, and never load one from a source you would not run
code from. Share the non-secret parts of a profile (endpoints, field names,
table names); each user keeps the secrets in their own keyring or environment.

## Data in transit

- API connections use `https://` and send requests, next pages and redirects
  only to the origin of `base_url`, so a token cannot reach another server
  (#30). Plain `http://` to a non-loopback host needs `allow_http = TRUE` and
  warns.
- SQL Server profiles connect with Driver 18, encrypted, verifying the server's
  certificate (#31). Turning either protection off warns on every connect.
- A connection built by hand with `DBI::dbConnect()` is the user's own: set
  `Encrypt` there yourself.

## Safeguards in this repo

- `.gitignore` is deny-by-default for data formats and credential files; the
  one shipped fixture is whitelisted by path.
- Local pre-commit hook (pii-guard + gitleaks) blocks staged PII and secrets.
  It is per clone: run `install_precommit.sh` from pii-guard after cloning.
- Code that touches PII is developed against synthetic data.

## If something leaks

Follow the pii-guard sandbox remediation protocol: back up, rewrite history in a
throwaway clone, verify with count-only checks, force-push, clean the server,
realign local copies, rotate any exposed credential.
