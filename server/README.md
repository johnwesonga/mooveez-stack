# Mooveez server

The Mooveez server is a Gleam/Wisp HTTP service that proxies requests to [The Movie Database (TMDB) API](https://developer.themoviedb.org/docs). It keeps the TMDB API key on the server and maintains a small in-memory cache to reduce repeated upstream requests.

## Features

- Movie search and movie-detail endpoints
- Server-side TMDB API-key handling
- In-memory caching of successful TMDB responses for 10 minutes
- `x-cache: HIT` and `x-cache: MISS` response headers
- Request logging, crash recovery, and `HEAD` handling through Wisp middleware

## Requirements

- Gleam (verified with 1.14.0)
- Erlang/OTP
- A [TMDB API key](https://developer.themoviedb.org/docs/getting-started)

## Configuration

Set `TMDB_API_KEY` in the environment before starting the server:

```sh
export TMDB_API_KEY="your-tmdb-api-key"
```

The server listens on port `8000`. The port and TMDB base URL are currently constants in `src/server.gleam`.

## Run

```sh
cd server
TMDB_API_KEY="your-tmdb-api-key" gleam run
```

The API is then available at `http://localhost:8000`.

## API

### Search for movies

```http
GET /api/search/movie?query=matrix&page=1
```

- `query` is required and must not be empty.
- `page` is optional and defaults to `1`.
- Query text is percent-encoded before the request is sent to TMDB.

### Get movie details

```http
GET /api/movie/603
```

The server passes TMDB's JSON body and HTTP status through to the client. Successful (`200`) upstream responses are cached. Network or request-construction failures return `500`; unknown local routes return `404`.

You can verify the service directly:

```sh
curl -i "http://localhost:8000/api/search/movie?query=matrix&page=1"
curl -i "http://localhost:8000/api/movie/603"
```

Repeat a request within 10 minutes to see `x-cache: HIT`. The first uncached response reports `x-cache: MISS`.

## Cache behavior

`src/cache.gleam` runs a Gleam OTP actor backed by an in-memory dictionary. Entries expire 600 seconds after insertion. The cache is local to the running process, has no persistence, and is cleared whenever the server restarts.

Only successful TMDB responses are stored. Expired entries are treated as misses; they are replaced the next time the same resource is fetched successfully.

## Test and format

```sh
cd server
gleam test
gleam format --check src test
```

The tests exercise local routing, search-query validation, cached responses, cache misses, and cache retrieval without making live TMDB requests. Upstream failures and time-based cache expiry are not yet covered.

## Production-style serving

The server provides only the `/api` routes. From the repository root, Caddy serves the built frontend and forwards `/api/*` to this process. See the [root README](../README.md) for the complete workflow.
