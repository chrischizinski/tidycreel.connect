# Data handling

tidycreel.connect is a connector package. It reads an agency’s creel
data at run time, through a connection the user supplies (CSV paths, a
DBI database or a REST API). It stores no survey data of its own.

## Where sensitive data lives

| Data | Location (outside this repo) | Contains PII? | Custodian |
|----|----|----|----|
| Agency creel interviews, counts, catch and lengths | The agency’s database or API, reached through [`creel_connect()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect.md) / [`creel_connect_api()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect_api.md) | Possibly (e.g. angler ZIP code, interviewer names) | The agency data steward |
| Shipped fixture: `inst/extdata/synthetic-boat-counts/counts.csv` | In this repo (whitelisted in `.gitignore`) | No: synthetic daily aggregate counts | Package maintainer |

PII never enters this repository. Test fixtures are synthetic, built in
test helpers or written to
[`tempdir()`](https://rdrr.io/r/base/tempfile.html), and never copied
from an agency extract.

## What analysts receive

- The fetch functions return what the connection is mapped to carry. Map
  only the fields an analysis needs; unmapped columns are dropped.
- Quasi-identifiers such as `zip_code` are summarised (by ZIP or
  county), not reported row by row.
- Small cells are suppressed per agency policy before results leave the
  secure environment.

## Credentials

- Never written in code or in a committed YAML profile. Profiles read
  them with `!expr Sys.getenv("VAR")`, and API tokens come from
  [`Sys.getenv()`](https://rdrr.io/r/base/Sys.getenv.html), the OS
  keyring (`keyring::key_get()`) or a token-provider function.
- Print methods never show a password or token; keep it that way.
- Use read-only database accounts.
- A credential that appears in a commit, log, or chat transcript is
  treated as compromised and rotated.

## Safeguards in this repo

- `.gitignore` is deny-by-default for data formats and credential files;
  the one shipped fixture is whitelisted by path.
- Local pre-commit hook (pii-guard + gitleaks) blocks staged PII and
  secrets. It is per clone: run `install_precommit.sh` from pii-guard
  after cloning.
- Code that touches PII is developed against synthetic data.

## If something leaks

Follow the pii-guard sandbox remediation protocol: back up, rewrite
history in a throwaway clone, verify with count-only checks, force-push,
clean the server, realign local copies, rotate any exposed credential.
