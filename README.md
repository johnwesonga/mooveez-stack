# Mooveez Full Stack 

Mooveez is a full-stack movie search application built entirely in [Gleam](https://gleam.run/). A Lustre single-page application provides search, pagination, and movie details; a Wisp backend proxies [TMDB](https://www.themoviedb.org/) so the API key remains private and repeated requests can be cached.

## Architecture

```text
Browser
  ├─ / and /movie/:id ──> Lustre client
  └─ /api/* ────────────> Caddy or Lustre dev proxy
                              └─> Wisp server :8000
                                    ├─> in-memory cache (10 minutes)
                                    └─> TMDB API
```

| Component | Technology | Location |
| --- | --- | --- |
| Web client | Gleam (JavaScript target), Lustre, Bootstrap | `client/` |
| API server | Gleam (Erlang target), Wisp, Mist | `server/` |
| Response cache | Gleam OTP actor | `server/src/cache.gleam` |
| Edge/static server | Caddy | `Caddyfile` |

## Features

- Search TMDB by movie title
- Paginated result cards with posters, ratings, and release dates
- Detail pages with overview, runtime, tagline, and genres
- Browser-safe API proxy: the TMDB key is never bundled into the client
- Ten-minute in-memory cache with observable `x-cache` headers
- SPA fallback through Caddy for direct visits to movie detail routes

## Requirements

- Gleam (verified with 1.14.0)
- Erlang/OTP
- Caddy 2 for the production-style local setup
- A [TMDB API key](https://developer.themoviedb.org/docs/getting-started)

## Quick start: development

Run the backend in one terminal:

```sh
cd server
TMDB_API_KEY="your-tmdb-api-key" gleam run
```

Run the Lustre development server in another:

```sh
cd client
./start.sh
```

Open the URL printed by Lustre. The client development configuration proxies `/api` to the backend at `http://localhost:8000`.

## Production-style local run

Build the browser application into the server's static directory:

```sh
cd client
gleam run -m lustre/dev build
cd ..
```

Start the API server:

```sh
cd server
TMDB_API_KEY="your-tmdb-api-key" gleam run
```

In a separate terminal, start Caddy from the repository root:

```sh
caddy run --config Caddyfile
```

Open <http://localhost:8080>. Caddy serves `server/priv/static`, sends `/api/*` to port `8000`, and falls back to `index.html` for client-side routes such as `/movie/603`.

## API overview

| Method | Endpoint | Description |
| --- | --- | --- |
| `GET` | `/api/search/movie?query=:query&page=:page` | Search movies; `page` defaults to `1` |
| `GET` | `/api/movie/:id` | Fetch one movie's details |

See [server/README.md](server/README.md) for response and cache behavior. See [client/README.md](client/README.md) for client routes, configuration, and build details.

## Testing and formatting

Each Gleam package is tested separately:

```sh
cd client
gleam test
gleam format --check src test

cd ../server
gleam test
gleam format --check src test
```

The client tests cover user-facing request error messages. The server tests cover local routing, query validation, cache retrieval, and cached HTTP responses without making live TMDB calls. Useful next coverage would include client routing and URL construction, plus mocked upstream failures and cache expiry.

## Project layout

```text
.
├── Caddyfile                 # Static serving, SPA fallback, and API proxy
├── client/
│   ├── gleam.toml            # JavaScript target and Lustre tool settings
│   ├── src/mooveez.gleam     # Client state, updates, routes, API calls, and UI
│   └── start.sh              # Starts the Lustre development server
└── server/
    ├── gleam.toml            # Erlang application dependencies
    ├── src/cache.gleam       # Ten-minute in-memory cache actor
    ├── src/server.gleam      # HTTP routes and TMDB proxy
    └── priv/static/          # Generated frontend deployment output
```

## Operational notes

- `TMDB_API_KEY` is read for uncached upstream calls. Keep it in the server environment and out of source control.
- The cache is per-process and is lost on restart; it is not shared between multiple server instances.
- Caddy expects the backend at `localhost:8000` and listens on `:8080`.
- Bootstrap and TMDB poster images require browser access to their respective CDNs.
