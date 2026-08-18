# Mooveez client

The Mooveez client is a browser application written in [Gleam](https://gleam.run/) with [Lustre](https://hexdocs.pm/lustre/). It searches for movies, displays paginated results, and shows movie details.

The client never calls TMDB directly. All data requests go to the local `/api` endpoint, which must be proxied to the Mooveez server. This keeps the TMDB API key out of browser code.

## Features

- Search movies by title
- Browse paginated search results
- View posters, release dates, ratings, and summaries
- Open a movie detail page with runtime, tagline, and genres
- Client-side routing for `/` and `/movie/:id`
- Loading, empty, and error states

## Requirements

- Gleam (verified with 1.14.0)
- A running Mooveez server on `http://localhost:8000`

The development server downloads project dependencies through Gleam as needed. Bootstrap is loaded from jsDelivr in the generated HTML, while poster images are loaded from TMDB's image CDN.

## Run in development

Start the backend first by following [the server instructions](../server/README.md). In a second terminal:

```sh
cd client
./start.sh
```

Alternatively, run the underlying command directly:

```sh
gleam run -m lustre/dev start
```

Open the URL printed by the Lustre development server. Its proxy forwards `/api/*` requests to `http://localhost:8000/api/*`, avoiding cross-origin configuration during local development.

## Build

```sh
cd client
gleam run -m lustre/dev build
```

The build configuration writes the generated HTML and JavaScript to `../server/priv/static`. That directory is served by Caddy in the full production-style setup.

## Test and format

```sh
cd client
gleam test
gleam format --check src test
```

## Routes and API calls

| Browser route | Purpose | API request |
| --- | --- | --- |
| `/` | Search and paginated results | `GET /api/search/movie?query=...&page=...` |
| `/movie/:id` | Movie details | `GET /api/movie/:id` |

The UI expects TMDB-compatible JSON responses from the backend. Application state, decoding, routing, effects, and views all live in `src/mooveez.gleam`.

## Configuration

Lustre's build, development proxy, generated page title, Bootstrap stylesheet, and Bootstrap script are configured in `gleam.toml`. The API prefix is the `proxy_url` constant in `src/mooveez.gleam`.

`index.html` is a standalone HTML file from an earlier/manual development flow; the normal Lustre build generates the deployable HTML in `server/priv/static` using the `[tools.lustre.html]` settings.
