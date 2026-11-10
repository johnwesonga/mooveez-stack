import cache
import gleam/http.{Get}
import gleam/option
import gleam/otp/actor
import gleeunit
import server
import wisp/simulate

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn unknown_route_returns_not_found_test() {
  let cache_subject = start_cache()
  let request = simulate.request(Get, "/not-a-route")
  let response = server.handle_request(request, cache_subject)

  assert response.status == 404
  assert simulate.read_body(response) == "Not found"
}

pub fn search_without_query_returns_bad_request_test() {
  let cache_subject = start_cache()
  let request = simulate.request(Get, "/api/search/movie")
  let response = server.handle_request(request, cache_subject)

  assert response.status == 400
  assert simulate.read_body(response) == "Bad request: error"
}

pub fn search_with_empty_query_returns_bad_request_test() {
  let cache_subject = start_cache()
  let request = simulate.request(Get, "/api/search/movie?query=&page=2")
  let response = server.handle_request(request, cache_subject)

  assert response.status == 400
}

pub fn movie_detail_with_non_numeric_id_returns_bad_request_test() {
  let cache_subject = start_cache()
  let request =
    simulate.request(Get, "/api/movie/603%3Fappend_to_response%3Dcredits")
  let response = server.handle_request(request, cache_subject)

  assert response.status == 400
  assert simulate.read_body(response) == "Bad request: invalid movie id"
}

pub fn movie_detail_with_zero_id_returns_bad_request_test() {
  let cache_subject = start_cache()
  let request = simulate.request(Get, "/api/movie/0")
  let response = server.handle_request(request, cache_subject)

  assert response.status == 400
}

pub fn cached_route_passes_through_response_test() {
  let cache_subject = start_cache()
  actor.send(cache_subject, cache.Set("movie:603", 200, "{\"id\":603}"))
  let request = simulate.request(Get, "/api/movie/603")
  let response = server.handle_request(request, cache_subject)

  assert response.status == 200
  assert simulate.read_body(response) == "{\"id\":603}"
  assert response.headers |> contains_header("x-cache", "HIT")
}

pub fn cache_returns_none_for_unknown_key_test() {
  let cache_subject = start_cache()
  let result =
    actor.call(cache_subject, waiting: 1000, sending: cache.Get("missing", _))

  assert result == option.None
}

pub fn cache_returns_stored_response_test() {
  let cache_subject = start_cache()
  actor.send(cache_subject, cache.Set("movie:603", 200, "{\"id\":603}"))
  let result =
    actor.call(cache_subject, waiting: 1000, sending: cache.Get("movie:603", _))

  let assert option.Some(entry) = result
  assert entry.status == 200
  assert entry.body == "{\"id\":603}"
}

fn start_cache() {
  let assert Ok(started) = cache.start()
  started.data
}

fn contains_header(headers, key: String, value: String) -> Bool {
  case headers {
    [] -> False
    [#(header_key, header_value), ..rest] ->
      case header_key == key && header_value == value {
        True -> True
        False -> contains_header(rest, key, value)
      }
  }
}
