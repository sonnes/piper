# Piper

Piper is a native macOS app that captures text into a local SQLite database and browses a folder of files. See [README.md](README.md) and [docs/README.md](docs/README.md).

## Build And Test

Use the Makefile for every build and test step.

| Target | Purpose |
| --- | --- |
| `make test` | Run all tests |
| `make build` | Build `build/Piper.app` |
| `make run` | Build and open the app |

Before you commit, run `make test`. When you correct a bug, add a test that fails without the fix.

## Code

- Put model code in a module under `Sources/Modules`. Put windows and views in `Sources/Piper`.
- Before you change the structure, read [docs/internals/architecture.md](docs/internals/architecture.md).
- Obey [docs/internals/coding-guidelines.md](docs/internals/coding-guidelines.md). Every class is `final`. KVO is banned. Keys, sizes, and colors go in `AppDefaults` and `PiperTheme`.
- Indent with four spaces.

## Docs

- If a change alters behavior that a user sees, update the matching page in `docs/guides/` or `docs/concepts/`.
- Guides describe current behavior only. Put unfinished work in `docs/release/readiness.md`.
- Start every doc page with `title`, `summary`, and `read_when` frontmatter.

## Git

- Start every commit subject with a present-tense verb.
- Do not add `output/`, `docs/plans/archive/`, or `.envrc` to Git.
