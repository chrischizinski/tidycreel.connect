# Helper: construct a creel_connection_api fixture for API backend tests.
# make_api_conn() returns a creel_connection_api object pointing at a dummy base_url.
# Tests wrap their calls in httr2::local_mocked_responses() to intercept HTTP.

make_api_conn <- function() {
  schema <- tidycreel::creel_schema(survey_type = "instantaneous")
  tidycreel.connect::creel_connect_api(
    base_url   = "http://test.example.com/api/",
    creel_uids = "test-uid-001",
    schema     = schema
  )
}
