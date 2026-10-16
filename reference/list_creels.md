# List all available creel surveys on a connection

Returns a data frame of all surveys available on the connected REST API.
Not supported for CSV connections, and inapplicable to database
connections: those address one set of tables rather than a catalogue of
surveys, and abort with class `creel_error_discovery_unavailable`.

## Usage

``` r
list_creels(conn, ...)
```

## Arguments

- conn:

  A `creel_connection` object created by
  [`creel_connect_api()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect_api.md).

- ...:

  Reserved for future arguments.

## Value

A data frame with columns: `creel_uid` (character), `title` (character),
`description` (character), `active` (logical), `data_complete`
(logical), `comments` (character).
