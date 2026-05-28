# Copilot instructions — dataproduct-builder-demo

This repository is a coding-agent plugin that helps build **Snowflake** dbt data products and integrate them with [Entropy Data](https://entropy-data.com). It is a streamlined demo derivative of [dataproduct-builder-dbt](https://github.com/entropy-data/dataproduct-builder-dbt).

Capabilities are exposed as **skills** — markdown files under `skills/<name>/SKILL.md` that the agent reads top-to-bottom and executes step by step.

## Routing

When a user request matches a skill's trigger, **read the corresponding `SKILL.md` start to finish before acting.**

| When the user asks about… | Follow this skill |
|---|---|
| Scaffolding a brand-new Snowflake dbt data product from scratch | `skills/dataproduct-bootstrap/SKILL.md` |
| Implementing a data product from a published Entropy Data URL or id, running dbt + OpenLineage + dbt tests + data contract tests | `skills/dataproduct-implement/SKILL.md` |
| Testing existing data contracts against the live Snowflake server | `skills/datacontract-test/SKILL.md` |

The trigger phrasing above is illustrative; each `SKILL.md`'s frontmatter `description` is authoritative.

## Resolving `${PLUGIN_ROOT}`

Skill files reference `${PLUGIN_ROOT}` to locate `templates/`. On Claude Code it is set automatically as `${CLAUDE_PLUGIN_ROOT}`. On Copilot / Codex / Cursor, it is **not** set — resolve it as the directory containing `AGENTS.md` and `skills/`.

## CLIs the skills shell out to

- **`entropy-data`** — fetch and publish data products / contracts.
- **`dbt`** (`dbt-snowflake` adapter) — required by both skills.
- **`dbt-ol`** (`openlineage-dbt`) — runs dbt with OpenLineage so lineage ships to Entropy Data on the spot.
- **`datacontract`** (`datacontract-cli[snowflake]`) — runs contract tests against Snowflake.

Per-project venv: every scaffolded project's `pyproject.toml` lists all four under `[dependency-groups].dev`. `uv sync` materializes `.venv/`; skills invoke as `uv run <cli> …`. The one exception is `dataproduct-bootstrap`'s pre-check (no `pyproject.toml` yet) — a global `uv tool install entropy-data` is needed once for that.

If `uv run <cli>` fails inside a project, the fix is `uv sync`; surface that and stop. Don't propose `uv tool install` as a fallback inside a project — it defeats version pinning.

## Conventions

- **Snowflake only.** If the user's dbt profile is not Snowflake, stop and point them at https://github.com/entropy-data/dataproduct-builder-dbt for the multi-platform builder.
- **Don't skip pre-checks.** Both skills verify CLI presence and Entropy Data connection first.
- **Don't overwrite existing files silently.** Surface the diff and ask.
- **Don't run `git init`, commit, or push.** Leave VCS state to the user.
- **Don't commit secrets.** API keys and warehouse credentials must come from env vars or repo secrets.
- **Idempotent re-runs**, except `dbt run` / `dbt test` / `datacontract test` which always execute.
