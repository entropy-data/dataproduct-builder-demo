# dataproduct-builder-demo — agent manifest

> **This file is the plugin's authoritative routing manifest, not a template.** It lives at the plugin's repo root and is meant to be **referenced** from your project (e.g. via Codex CLI's marketplace install, or a one-line pointer in your project's own `AGENTS.md`), not copied into your project. Updating the plugin updates this file in place.

This repository is a coding-agent plugin that helps build **Snowflake** dbt data products and integrate them with [Entropy Data](https://entropy-data.com). It is a streamlined demo derivative of [dataproduct-builder-dbt](https://github.com/entropy-data/dataproduct-builder-dbt). It exposes its capabilities as **skills** — markdown files under `skills/<name>/SKILL.md` that you read top-to-bottom and execute step by step.

When a user request matches a skill's trigger, **read the corresponding `SKILL.md` start to finish before acting.** Each skill contains audit steps, parameter-gathering, and explicit user-confirmation gates that must not be skipped.

## Skills

| When the user asks about… | Follow this skill |
|---|---|
| Scaffolding a brand-new Snowflake dbt data product from scratch (greenfield, empty directory) | `skills/dataproduct-bootstrap/SKILL.md` |
| Implementing a data product from a published Entropy Data URL or id, running dbt + OpenLineage + dbt tests + data contract tests end-to-end | `skills/dataproduct-implement/SKILL.md` |
| Testing existing data contracts against the live Snowflake server (no edits — just run `datacontract test`) | `skills/datacontract-test/SKILL.md` |

The trigger phrasing above is illustrative; each `SKILL.md`'s frontmatter `description` is authoritative.

## Resolving `${PLUGIN_ROOT}`

The skill files reference `${PLUGIN_ROOT}` to locate `templates/`. On Claude Code this is set automatically as `${CLAUDE_PLUGIN_ROOT}`; on Codex / Cursor / other agents reading this file, it is **not** set — resolve it as **the directory that contains this `AGENTS.md`** (the cloned repo root, which also contains `skills/`).

## CLIs the skills shell out to

- **`entropy-data`** (PyPI: `entropy-data`) — fetch data products and contracts, publish updates, list teams.
- **`dbt`** (`dbt-snowflake` adapter) — required at runtime by both skills.
- **`dbt-ol`** (PyPI: `openlineage-dbt`) — runs dbt with OpenLineage so the demo ships lineage to Entropy Data immediately during implementation.
- **`datacontract`** (PyPI: `datacontract-cli[snowflake]`) — runs contract tests against the Snowflake server defined in the ODCS file.

**Install pattern: per-project venv.** Every scaffolded project ships a `pyproject.toml` listing all four CLIs (plus dbt-snowflake) as dev deps. Running `uv sync` from the project root materializes `.venv/` with everything at the versions pinned in `uv.lock`. **All skills invoke these CLIs as `uv run <cli> …`** so the project's pinned version is the one that runs, independent of anything globally installed.

The one exception is `dataproduct-bootstrap`'s pre-check step: it runs against an empty directory before any `pyproject.toml` exists, so it requires a one-time globally available `entropy-data` (`uv tool install entropy-data`) for the initial DP / contract lookup. Once bootstrap scaffolds the project and runs `uv sync`, every subsequent skill uses the venv exclusively.

If `uv run <cli>` fails inside a project, surface `uv sync` from the project root as the fix and stop — do not install on the user's behalf without confirmation. Do not propose `uv tool install` as a fallback inside a project; that defeats version pinning.

## Conventions when running skills

- **Snowflake only.** This demo plugin intentionally drops multi-platform branching. For Databricks/BigQuery/Postgres support, point users at https://github.com/entropy-data/dataproduct-builder-dbt.
- **Don't skip the pre-checks.** Both skills verify CLI presence and Entropy Data connection before touching files.
- **Don't overwrite existing files silently.** Surface the diff and ask.
- **Don't run `git init`, commit, or push** on the user's behalf — leave VCS state to the user.
- **Don't commit secrets.** API keys and warehouse credentials must come from env vars or repo secrets.
- **Idempotent re-runs.** Running a skill a second time when everything is already in place should be a no-op, except for `dbt run` / `dbt test` / `datacontract test` which always re-execute by design.
