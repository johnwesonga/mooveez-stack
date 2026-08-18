import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleam/uri
import lustre
import lustre/attribute
import lustre/effect
import lustre/element
import lustre/event
import modem

import lustre/element/html
import rsvp

const tmdb_image_base = "https://image.tmdb.org/t/p/w342"

const proxy_url = "/api"

pub type Movie {
  Movie(
    id: Int,
    title: String,
    overview: String,
    release_date: String,
    poster_path: option.Option(String),
    vote_average: Float,
  )
}

fn movie_decoder() -> decode.Decoder(Movie) {
  use id <- decode.field("id", decode.int)
  use title <- decode.field("title", decode.string)
  use overview <- decode.field("overview", decode.string)
  use release_date <- decode.field("release_date", decode.string)
  use poster_path <- decode.field("poster_path", decode.optional(decode.string))
  use vote_average <- decode.field("vote_average", decode.float)
  decode.success(Movie(
    id:,
    title:,
    overview:,
    release_date:,
    poster_path:,
    vote_average:,
  ))
}

pub type SearchResponse {
  SearchResponse(results: List(Movie), total_pages: Int, total_results: Int)
}

fn search_response_decoder() -> decode.Decoder(SearchResponse) {
  use results <- decode.field("results", decode.list(movie_decoder()))
  use total_pages <- decode.field("total_pages", decode.int)
  use total_results <- decode.field("total_results", decode.int)
  decode.success(SearchResponse(results:, total_pages:, total_results:))
}

pub type Route {
  Home
  Details(Int)
  NotFound
}

pub type MovieDetail {
  MovieDetail(
    id: Int,
    title: String,
    overview: String,
    release_date: String,
    poster_path: option.Option(String),
    vote_average: Float,
    runtime: option.Option(Int),
    tagline: String,
    genres: List(String),
  )
}

fn genre_decoder() -> decode.Decoder(String) {
  use name <- decode.field("name", decode.string)
  decode.success(name)
}

fn movie_detail_decoder() -> decode.Decoder(MovieDetail) {
  use id <- decode.field("id", decode.int)
  use title <- decode.field("title", decode.string)
  use overview <- decode.field("overview", decode.string)
  use release_date <- decode.field("release_date", decode.string)
  use poster_path <- decode.field("poster_path", decode.optional(decode.string))
  use vote_average <- decode.field("vote_average", decode.float)
  use runtime <- decode.field("runtime", decode.optional(decode.int))
  use tagline <- decode.field("tagline", decode.string)
  use genres <- decode.field("genres", decode.list(genre_decoder()))
  decode.success(MovieDetail(
    id:,
    title:,
    overview:,
    release_date:,
    poster_path:,
    vote_average:,
    runtime:,
    tagline:,
    genres:,
  ))
}

pub type Model {
  Model(
    query: String,
    movies: List(Movie),
    loading: Bool,
    error: option.Option(String),
    total_pages: Int,
    current_page: Int,
    route: Route,
    movie_detail: option.Option(MovieDetail),
    detail_loading: Bool,
    detail_error: option.Option(String),
  )
}

fn load_route(model: Model, route: Route) -> #(Model, effect.Effect(Msg)) {
  case route {
    Details(id) -> #(
      Model(
        ..model,
        route: route,
        movie_detail: option.None,
        detail_error: option.None,
        detail_loading: True,
      ),
      fetch_movie_detail(id),
    )
    _ -> #(Model(..model, route: route), effect.none())
  }
}

pub fn init(_flags) -> #(Model, effect.Effect(Msg)) {
  let initial_route =
    modem.initial_uri()
    |> result.map(parse_route)
    |> result.unwrap(Home)

  let #(model, route_effect) =
    load_route(
      Model(
        query: "",
        movies: [],
        loading: False,
        error: option.None,
        total_pages: 1,
        current_page: 1,
        route: Home,
        movie_detail: option.None,
        detail_loading: False,
        detail_error: option.None,
      ),
      initial_route,
    )

  #(model, effect.batch([modem.init(on_url_change), route_effect]))
}

pub type Msg {
  UserUpdatedQuery(String)
  UserSubmittedSearch
  ApiGotMovies(Result(SearchResponse, rsvp.Error(String)))
  ApiGotMovieDetail(Result(MovieDetail, rsvp.Error(String)))
  UserChangePage(Int)
  OnRouteChange(Route)
}

pub fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    ApiGotMovies(Ok(response)) -> #(
      Model(
        ..model,
        movies: response.results,
        loading: False,
        error: option.None,
        total_pages: response.total_pages,
      ),
      effect.none(),
    )

    ApiGotMovies(Error(err)) -> {
      echo err
      #(
        Model(
          ..model,
          movies: [],
          loading: False,
          error: option.Some(error_to_string(err)),
        ),
        effect.none(),
      )
    }
    UserUpdatedQuery(query) -> #(
      Model(..model, query: query, current_page: 1),
      effect.none(),
    )
    UserSubmittedSearch -> #(
      Model(..model, loading: True, current_page: 1),
      fetch_movies(model.query, 1),
    )
    UserChangePage(page) -> #(
      Model(..model, loading: True, current_page: page),
      fetch_movies(model.query, page),
    )
    OnRouteChange(route) -> load_route(model, route)

    ApiGotMovieDetail(Ok(detail)) -> #(
      Model(
        ..model,
        movie_detail: option.Some(detail),
        detail_loading: False,
        detail_error: option.None,
      ),
      effect.none(),
    )

    ApiGotMovieDetail(Error(err)) -> #(
      Model(
        ..model,
        movie_detail: option.None,
        detail_loading: False,
        detail_error: option.Some(error_to_string(err)),
      ),
      effect.none(),
    )
  }
}

fn fetch_movie_detail(id: Int) -> effect.Effect(Msg) {
  let url = proxy_url <> "/movie/" <> int.to_string(id)
  let handler = rsvp.expect_json(movie_detail_decoder(), ApiGotMovieDetail)
  rsvp.get(url, handler)
}

pub fn fetch_movies(query: String, page: Int) -> effect.Effect(Msg) {
  let trimmed_query = string.trim(query)
  case string.is_empty(trimmed_query) {
    True -> effect.none()
    False -> {
      let url = build_search_url(trimmed_query, page)
      let handler = rsvp.expect_json(search_response_decoder(), ApiGotMovies)
      rsvp.get(url, handler)
    }
  }
}

fn build_search_url(query: String, page: Int) -> String {
  let encoded_query = uri.percent_encode(query)
  proxy_url
  <> "/search/movie?"
  <> "query="
  <> encoded_query
  <> "&page="
  <> int.to_string(page)
}

pub fn error_to_string(error: rsvp.Error(String)) -> String {
  case error {
    rsvp.BadUrl(url) -> "Invalid request URL: " <> url

    rsvp.BadBody -> "The server sent back something we couldn't read."

    rsvp.NetworkError ->
      "Couldn't reach TMDB. Check your connection and try again."

    rsvp.HttpError(response) ->
      "TMDB returned an error (status "
      <> int.to_string(response.status)
      <> "). Please try again."

    rsvp.UnhandledResponse(response) ->
      "Unexpected response from TMDB (status "
      <> int.to_string(response.status)
      <> ")."

    rsvp.JsonError(json_error) ->
      "Couldn't parse TMDB's response: " <> json_error_to_string(json_error)
  }
}

fn json_error_to_string(error: json.DecodeError) -> String {
  case error {
    json.UnexpectedEndOfInput -> "the response ended unexpectedly."
    json.UnexpectedByte(byte) ->
      "found an unexpected character (" <> byte <> ") in the response."
    json.UnexpectedSequence(seq) ->
      "found an unexpected sequence (" <> seq <> ") in the response."
    json.UnableToDecode(_) -> "the response didn't match the shape we expected."
  }
}

// VIEWS 

pub fn view(model: Model) -> element.Element(Msg) {
  case model.route {
    Home -> home_view(model)
    Details(_) -> detail_view(model)
    NotFound -> not_found_view()
  }
}

fn home_view(model: Model) -> element.Element(Msg) {
  html.div([attribute.class("container py-4")], [
    html.h1([attribute.class("mb-4")], [element.text("Mooveez")]),
    search_form(model),
    result_section(model),
  ])
}

fn not_found_view() -> element.Element(Msg) {
  html.div([attribute.class("container py-4")], [
    html.h1([], [element.text("Page not found")]),
    html.a([attribute.href("/")], [element.text("← Back to search")]),
  ])
}

fn detail_view(model: Model) -> element.Element(Msg) {
  html.div([attribute.class("container py-4")], [
    html.a([attribute.href("/"), attribute.class("btn btn-link mb-3")], [
      element.text("← Back to search"),
    ]),
    case model.detail_error {
      option.Some(message) ->
        html.div([attribute.class("alert alert-danger")], [
          element.text(message),
        ])
      option.None ->
        case model.detail_loading, model.movie_detail {
          True, _ ->
            html.p([attribute.class("text-muted")], [element.text("Loading...")])
          False, option.Some(detail) -> movie_detail_card(detail)
          False, option.None ->
            html.p([attribute.class("text-muted")], [
              element.text("Movie not found."),
            ])
        }
    },
  ])
}

fn movie_detail_card(detail: MovieDetail) -> element.Element(Msg) {
  html.div([attribute.class("row g-4")], [
    html.div([attribute.class("col-md-4")], [
      poster_image(detail.poster_path, detail.title),
    ]),
    html.div([attribute.class("col-md-8")], [
      html.h2([], [element.text(detail.title)]),
      case detail.tagline {
        "" -> element.text("")
        tagline ->
          html.p([attribute.class("text-muted fst-italic")], [
            element.text(tagline),
          ])
      },
      html.p([], [element.text(detail.overview)]),
      html.ul([attribute.class("list-unstyled")], [
        html.li([], [element.text("Release date: " <> detail.release_date)]),
        html.li([], [
          element.text("Rating: ⭐ " <> float.to_string(detail.vote_average)),
        ]),
        html.li([], [
          element.text("Runtime: " <> runtime_to_string(detail.runtime)),
        ]),
        html.li([], [
          element.text("Genres: " <> string.join(detail.genres, ", ")),
        ]),
      ]),
    ]),
  ])
}

fn runtime_to_string(runtime: option.Option(Int)) -> String {
  case runtime {
    option.Some(minutes) -> int.to_string(minutes) <> " min"
    option.None -> "Unknown"
  }
}

fn search_form(model: Model) -> element.Element(Msg) {
  html.form(
    [
      attribute.class("d-flex gap-2 mb-4"),
      event.on_submit(fn(_fields) { UserSubmittedSearch }),
    ],
    [
      html.input([
        attribute.type_("text"),
        attribute.class("form-control"),
        attribute.placeholder("Search for a movie..."),
        attribute.value(model.query),
        event.on_input(UserUpdatedQuery),
      ]),
      html.button(
        [
          attribute.type_("submit"),
          attribute.class("btn btn-primary"),
          attribute.disabled(model.loading),
        ],
        [
          element.text(case model.loading {
            True -> "Searching..."
            False -> "Search"
          }),
        ],
      ),
    ],
  )
}

fn result_section(model: Model) -> element.Element(Msg) {
  case model.error {
    option.Some(message) ->
      html.div([attribute.class("alert alert-danger")], [element.text(message)])
    option.None ->
      case model.loading, model.movies {
        True, _ ->
          html.p([attribute.class("text-muted")], [element.text("Loading...")])
        False, [] ->
          html.p([attribute.class("text-muted")], [
            element.text("No results yet."),
          ])
        False, movies ->
          html.div([], [
            html.div([attribute.class("row g-3")], list.map(movies, movie_card)),
            pagination_section(model.current_page, model.total_pages),
          ])
      }
  }
}

fn pagination_section(
  current_page: Int,
  total_pages: Int,
) -> element.Element(Msg) {
  case total_pages <= 1 {
    True -> element.text("")
    False ->
      html.nav([attribute.class("d-flex justify-content-center mt-4")], [
        html.ul(
          [attribute.class("pagination")],
          list.flatten([
            [nav_link("Previous", current_page - 1, current_page > 1)],
            list.map(page_window(current_page, total_pages), fn(page) {
              page_link(page, current_page)
            }),
            [nav_link("Next", current_page + 1, current_page < total_pages)],
          ]),
        ),
      ])
  }
}

// A small window of page numbers centered on the current page,
// clamped to valid bounds — avoids rendering all 500 possible TMDB pages.
fn page_window(current_page: Int, total_pages: Int) -> List(Int) {
  let window_size = 2
  let start = int.max(1, current_page - window_size)
  let end = int.min(total_pages, current_page + window_size)
  range_inclusive(start, end)
}

fn range_inclusive(start: Int, end: Int) -> List(Int) {
  case start > end {
    True -> []
    False -> [start, ..range_inclusive(start + 1, end)]
  }
}

fn nav_link(
  label: String,
  target_page: Int,
  enabled: Bool,
) -> element.Element(Msg) {
  html.li(
    [
      attribute.class(case enabled {
        True -> "page-item"
        False -> "page-item disabled"
      }),
    ],
    [
      html.button(
        [
          attribute.class("page-link"),
          attribute.type_("button"),
          attribute.disabled(!enabled),
          event.on_click(UserChangePage(target_page)),
        ],
        [element.text(label)],
      ),
    ],
  )
}

fn page_link(page: Int, current_page: Int) -> element.Element(Msg) {
  html.li(
    [
      attribute.class(case page == current_page {
        True -> "page-item active"
        False -> "page-item"
      }),
    ],
    [
      html.button(
        [
          attribute.class("page-link"),
          attribute.type_("button"),
          event.on_click(UserChangePage(page)),
        ],
        [element.text(int.to_string(page))],
      ),
    ],
  )
}

fn movie_card(movie: Movie) -> element.Element(Msg) {
  html.a(
    [
      attribute.href("/movie/" <> int.to_string(movie.id)),
      attribute.class("col-6 col-md-4 col-lg-3 text-decoration-none text-reset"),
    ],
    [
      html.div([attribute.class("card h-100")], [
        poster_image(movie.poster_path, movie.title),
        html.div([attribute.class("card-body")], [
          html.h5([attribute.class("card-title")], [element.text(movie.title)]),
          html.p([attribute.class("card-text text-muted small")], [
            element.text(movie.overview),
          ]),
          release_date(movie.release_date),
          html.p([attribute.class("card-text")], [
            element.text("⭐ " <> float.to_string(movie.vote_average)),
          ]),
        ]),
      ]),
    ],
  )
}

fn release_date(release_date: String) {
  case release_date {
    "" -> {
      html.p([attribute.class("card-text text-muted small")], [
        element.text("Release date unknown"),
      ])
    }
    _ -> {
      html.p([attribute.class("card-text text-muted small")], [
        element.text(release_date),
      ])
    }
  }
}

fn poster_image(
  poster_path: option.Option(String),
  title: String,
) -> element.Element(Msg) {
  case poster_path {
    option.Some(path) ->
      html.img([
        attribute.class("card-img-top"),
        attribute.src(tmdb_image_base <> path),
        attribute.alt(title),
      ])
    option.None ->
      html.div(
        [
          attribute.class(
            "card-img-top bg-secondary d-flex align-items-center justify-content-center text-white",
          ),
          attribute.style("height", "465px"),
        ],
        [element.text("No image")],
      )
  }
}

fn parse_route(uri: uri.Uri) -> Route {
  case uri.path_segments(uri.path) {
    [] -> Home
    ["movie", id_string] ->
      case int.parse(id_string) {
        Ok(id) -> Details(id)
        Error(_) -> NotFound
      }
    _ -> NotFound
  }
}

fn on_url_change(uri: uri.Uri) -> Msg {
  OnRouteChange(parse_route(uri))
}

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}
