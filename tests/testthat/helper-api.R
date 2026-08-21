# Helper: construct a creel_connection_api fixture for API backend tests.
#
# Every endpoint path and field name below is invented. The package ships none
# for any organisation's API, so a test connection has to describe one, exactly
# as a user does -- which is also what keeps these tests from encoding anyone's
# real schema.
#
# Tests wrap their calls in httr2::local_mocked_responses() to intercept HTTP.

test_api_endpoints <- function() {
  list(
    interviews      = "v2/interviews",
    counts          = "v2/counts",
    catch           = "v2/catch",
    harvest_lengths = "v2/lengths/harvest",
    release_lengths = "v2/lengths/release",
    discovery       = "v2/surveys"
  )
}

test_api_field_map <- function() {
  list(
    interviews = list(
      interview_uid  = "InterviewID",
      date           = "SurveyDate",
      trip_status    = "TripStatus",
      effort_hours   = "HoursFished",
      effort_minutes = "MinutesFished"
    ),
    counts = list(
      date          = "SurveyDate",
      bank_anglers  = "ShoreAnglers",
      angler_boats  = "FishingBoats",
      non_ang_boats = "OtherBoats"
    ),
    catch = list(
      interview_uid = "InterviewID",
      species       = "SpeciesCode",
      catch_count   = "FishCount",
      catch_type    = "CatchCategory"
    ),
    harvest_lengths = list(
      interview_uid = "InterviewID",
      species       = "SpeciesCode",
      length_mm     = "LengthMM"
    ),
    release_lengths = list(
      interview_uid = "InterviewID",
      species       = "SpeciesCode",
      length_mm     = "LengthMM"
    ),
    discovery = list(
      creel_uid     = "SurveyID",
      title         = "SurveyTitle",
      description   = "SurveyDescription",
      active        = "IsActive",
      data_complete = "IsComplete",
      comments      = "Notes"
    )
  )
}

make_api_conn <- function(field_map = test_api_field_map(),
                          endpoints = test_api_endpoints(),
                          schema    = tidycreel::creel_schema(survey_type = "instantaneous")) {
  tidycreel.connect::creel_connect_api(
    base_url      = "http://test.example.com/api/",
    creel_uids    = "test-uid-001",
    schema        = schema,
    uid_param     = "survey_id",
    endpoints     = endpoints,
    api_field_map = field_map
  )
}
