# Security policy

tidycreel.connect reads creel survey data from files, databases and REST APIs
using credentials the user supplies. The data it returns can include personal
information about anglers. Reports of anything that could expose a credential
or that data are welcome.

## Reporting a vulnerability

Please report privately, not in a public issue:

- Use GitHub's **Report a vulnerability** button on the
  [Security tab](https://github.com/chrischizinski/tidycreel.connect/security)
  of this repository, or
- email the maintainer at the address in `DESCRIPTION`.

Include what you found, how to reproduce it, and which version or commit you
used. Do **not** include real credentials or real survey records; a
description of their shape is enough.

You should get an acknowledgement within a week. Once a fix is released, the
report can be disclosed, with credit if you want it.

## In scope

- A credential (database password, API token or key) sent somewhere it
  should not go, unencrypted, or shown in output, a log or an error message.
- Personal data in the returned rows exposed beyond what the connection is
  mapped to carry.
- The package's CI or release process being usable to change the code users
  install.

## Supported versions

Only the latest commit on `main` is supported. There are no maintained
release branches.
