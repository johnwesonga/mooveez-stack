import cache
import envoy
import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/int
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/result
import gleam/string
import gleam/uri

import mist
import wisp.{type Request, type Response}
import wisp/wisp_mist

const tmdb_base_url = "https://api.themoviedb.org/3"

pub fn main() -> Nil {
  wisp.configure_logger()
  let secret_key_base = wisp.random_string(64)

  let assert Ok(cache_actor) = cache.start()
  let cache_subject = cache_actor.data
  let handler = fn(req) { handle_request(req, cache_subject) }

  let assert Ok(_) =
    wisp_mist.handler(handler, secret_key_base)
    |> mist.new
    |> mist.port(8000)
    |> mist.start
  process.sleep_forever()
}

pub fn handle_request(
  req: Request,
  cache_subject: process.Subject(cache.CacheMessage),
) -> Response {
  use req <- middleware(req)
  case wisp.path_segments(req) {
    ["api", "search", "movie"] -> handle_search(req, cache_subject)
    ["api", "movie", id_string] -> handle_movie_detail(id_string, cache_subject)
    _ -> wisp.not_found()
  }
}

fn handle_movie_detail(
  id_string: String,
  cache_subject: process.Subject(cache.CacheMessage),
) -> Response {
  case int.parse(id_string) {
    Ok(id) if id > 0 ->
      proxy_tmdb(
        "movie:" <> int.to_string(id),
        "/movie/" <> int.to_string(id),
        cache_subject,
      )
    _ -> wisp.bad_request("invalid movie id")
  }
}

pub fn middleware(
  req: wisp.Request,
  handle_request: fn(Request) -> Response,
) -> Response {
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use req <- wisp.handle_head(req)
  handle_request(req)
}

fn get_param(
  pairs: List(#(String, String)),
  key: String,
) -> Result(String, Nil) {
  pairs
  |> list.find(fn(pair) { pair.0 == key })
  |> result.map(fn(pair) { pair.1 })
}

fn handle_search(
  req: Request,
  cache_subject: process.Subject(cache.CacheMessage),
) -> Response {
  let query_params = request.get_query(req) |> result.unwrap([])
  let query = get_param(query_params, "query") |> result.unwrap("")
  let page = get_param(query_params, "page") |> result.unwrap("1")

  case string.is_empty(query) {
    True -> wisp.bad_request("error")
    False -> {
      let cache_key = "search:" <> query <> ":" <> page
      let path =
        "/search/movie?query=" <> uri.percent_encode(query) <> "&page=" <> page
      proxy_tmdb(cache_key, path, cache_subject)
    }
  }
}

fn proxy_tmdb(
  cache_key: String,
  path: String,
  cache_subject: process.Subject(cache.CacheMessage),
) -> Response {
  case
    actor.call(cache_subject, waiting: 1000, sending: cache.Get(cache_key, _))
  {
    option.Some(entry) -> {
      wisp.log_info("cache HIT: " <> cache_key)
      wisp.json_response(entry.body, entry.status)
      |> response.set_header("x-cache", "HIT")
    }
    option.None -> {
      wisp.log_info("cache MISS: " <> cache_key)
      fetch_and_cache(cache_key, path, cache_subject)
    }
  }
}

fn fetch_and_cache(
  cache_key: String,
  path: String,
  cache_subject: process.Subject(cache.CacheMessage),
) -> Response {
  let api_key = envoy.get("TMDB_API_KEY") |> result.unwrap("")
  let separator = case string.contains(path, "?") {
    True -> "&"
    False -> "?"
  }
  let url = tmdb_base_url <> path <> separator <> "api_key=" <> api_key

  case request.to(url) {
    Error(_) -> wisp.internal_server_error()
    Ok(tmdb_req) ->
      case httpc.send(tmdb_req) {
        Ok(tmdb_resp) -> {
          case tmdb_resp.status {
            200 ->
              process.send(
                cache_subject,
                cache.Set(cache_key, tmdb_resp.status, tmdb_resp.body),
              )
            _ -> Nil
          }
          wisp.json_response(tmdb_resp.body, tmdb_resp.status)
          |> response.set_header("x-cache", "MISS")
        }
        Error(_) -> wisp.internal_server_error()
      }
  }
}
