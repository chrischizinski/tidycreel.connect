# Check available ODBC drivers

`creel_check_driver()` lists all ODBC drivers registered on the current
system and reports whether a SQL Server-compatible driver is present.
This is a diagnostic function intended for setup verification – it does
not create a connection.

Requires the `odbc` package and an OS-level ODBC driver manager
(unixODBC on macOS/Linux, or the Windows ODBC Data Source
Administrator).

## Usage

``` r
creel_check_driver()
```

## Value

`invisible(NULL)` – called for side-effect cli output only.

## Examples

``` r
if (FALSE) { # \dontrun{
creel_check_driver()
} # }
```
