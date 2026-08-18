import gleam/http/response
import gleam/json
import gleeunit
import mooveez
import rsvp

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn bad_url_error_includes_url_test() {
  let message = mooveez.error_to_string(rsvp.BadUrl("not a url"))

  assert message == "Invalid request URL: not a url"
}

pub fn network_error_is_actionable_test() {
  let message = mooveez.error_to_string(rsvp.NetworkError)

  assert message == "Couldn't reach TMDB. Check your connection and try again."
}

pub fn http_error_includes_status_test() {
  let message =
    response.new(429)
    |> rsvp.HttpError
    |> mooveez.error_to_string

  assert message == "TMDB returned an error (status 429). Please try again."
}

pub fn unhandled_response_includes_status_test() {
  let message =
    response.new(304)
    |> rsvp.UnhandledResponse
    |> mooveez.error_to_string

  assert message == "Unexpected response from TMDB (status 304)."
}

pub fn json_error_describes_shape_mismatch_test() {
  let message =
    json.UnableToDecode([])
    |> rsvp.JsonError
    |> mooveez.error_to_string

  assert message
    == "Couldn't parse TMDB's response: the response didn't match the shape we expected."
}
