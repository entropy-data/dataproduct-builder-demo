---
name: dataproduct-bootstrap
description: Bootstrap a brand-new Snowflake dbt data product from scratch in one go — dbt_project.yml, model layout, README, .gitignore, profiles.yml.example for Snowflake, ODPS, output-port ODCS, openlineage.yml, and a GitHub Actions workflow. Trigger when the user asks to start a new data product, scaffold a new dbt project, or "create a Snowflake data product from scratch."
---

# Bootstrap a new Snowflake dbt data product (demo)

Scaffold a Snowflake-only dbt data product following the Entropy Data conventions. Demo-grade: one batched question, one platform, no audits, no migration logic.

For populating the contract schema and dbt model bodies from a published data product, use the **dataproduct-implement** skill after this one.

## What this skill produces

After running, the directory contains (layout follows [the guide](https://www.entropy-data.com/learn/data-products-with-dbt)):

```
.
├── dbt_project.yml
├── .gitignore
├── README.md
├── profiles.yml.example
├── <data-product-id>.odps.yaml
├── openlineage.yml
├── .github/workflows/data-product.yml
├── datacontracts/
│   └── <table>_v1.odcs.yaml
├── models/
│   ├── input_ports/sources.yml
│   ├── staging/
│   ├── intermediate/
│   └── output_ports/
│       └── <table>.yml
└── tests/
    └── assert_updated_at_not_in_future.sql
```

## How to run this skill

> `${PLUGIN_ROOT}` below refers to the root of this plugin — the directory that contains `skills/`. On Claude Code it is set automatically as `${CLAUDE_PLUGIN_ROOT}`; use that. On any other agent (Codex, Copilot CLI, etc.) it is unset; resolve it as `../..` relative to **this `SKILL.md` file's directory** (i.e. the grandparent of `skills/<this-skill>/`).

### Plan announcement (before Step 1)

Before running Step 1, print this plan to the user verbatim:

> Running **dataproduct-bootstrap**. I'll:
> 1. Pre-check: confirm the working directory is empty.
> 2. Ask you for parameters in one batched question (id, name, purpose, team, Snowflake database, output port table).
> 3. Scaffold the dbt project (dbt_project.yml, profiles.yml.example, model layout, README, .gitignore).
> 4. Scaffold the publishing layer (ODPS, output-port ODCS, openlineage.yml, GitHub Actions workflow).
> 5. Summarize what was scaffolded and the next manual steps.

Then proceed.

### Step 1 — Pre-checks

- Confirm the working directory is empty, or contains only files the user is fine with (e.g. an empty git repo, a `LICENSE`, or a placeholder `README.md` that will be overwritten).
- If `dbt_project.yml` already exists, stop and tell the user this demo skill only handles greenfield directories. Point them at `dataproduct-implement` to add models to an existing project.

### Step 2 — Gather parameters in one batched question

Ask the user for these in a single prompt. Do not generate any files until you have all of them.

| Parameter | Description | Example |
|---|---|---|
| `DATA_PRODUCT_ID` | Stable id, snake_case, also the dbt project name | `dp_acme_customer_activity` |
| `DATA_PRODUCT_NAME` | Human-friendly name | `Customer Activity` |
| `PURPOSE` | One sentence — why this data product exists | `Customer activity for customer success.` |
| `TEAM_NAME` | Owning team id (free-text accepted for the demo) | `customer-success` |
| `DATABASE` | Snowflake database | `ENTROPY_DATA_PROD` |
| `TABLE` | First output port table name | `customer_activity` |

Derive (per https://www.entropy-data.com/learn/data-products-with-dbt):

- `DBT_PROJECT_NAME` = `DATA_PRODUCT_ID` — also the dbt profile name and the profile's default schema (the *internal* layer: staging + intermediate models materialize here).
- `OUTPUT_PORT_NAME` = `DATA_PRODUCT_ID`
- `CONTRACT_ID` = `<DATA_PRODUCT_ID>-v1`
- `CONTRACT_FILE` = `<TABLE>_v1.odcs.yaml` — snake-case table name + major version, matching what `dataproduct-implement` writes.
- `CONTRACT_PATH` = `datacontracts/<CONTRACT_FILE>`
- `ODPS_FILE` = `<DATA_PRODUCT_ID>.odps.yaml`
- `OUTPUT_PORT_SCHEMA` = `<DBT_PROJECT_NAME>_OP_V1` — the schema dbt produces by concatenating the profile schema with the output port model's `schema='op_v1'` override. This is the schema the data contract and the platform's integration scan target. Snowflake uppercases unquoted identifiers, so this value is uppercase regardless of how `DATA_PRODUCT_ID` was entered.

Resolve `API_HOST` from the entropy-data CLI connection: `entropy-data connection get -o json` → `host`. If the CLI is not connected, stop and tell the user to run `entropy-data connection add <name> --host <host> --api-key <key>` first. The demo does not run without a working connection.

Always use the `entropy-data` CLI for any connection to Entropy Data. Do not use the Entropy Data MCP server.

### Step 3 — Scaffold the project

Templates live under `${PLUGIN_ROOT}/skills/dataproduct-bootstrap/templates/`. Copy each one into the working directory, substituting placeholders.

| Template | Destination |
|---|---|
| `dbt_project.yml` | `dbt_project.yml` |
| `.gitignore` | `.gitignore` |
| `README.md` | `README.md` |
| `profiles.yml.example` | `profiles.yml.example` |
| `data-product.odps.yaml` | `<DATA_PRODUCT_ID>.odps.yaml` |
| `openlineage.yml` | `openlineage.yml` |
| `models/input_ports/sources.yml` | `models/input_ports/sources.yml` |
| `models/output_ports/_model.yml` | `models/output_ports/<TABLE>.yml` |
| `datacontracts/contract.odcs.yaml` | `<CONTRACT_PATH>` |
| `tests/assert_updated_at_not_in_future.sql` | `tests/assert_updated_at_not_in_future.sql` |
| `.github/workflows/data-product.yml` | `.github/workflows/data-product.yml` |

Also create empty `models/staging/`, `models/intermediate/`, `analyses/`, `macros/`, `seeds/`, `snapshots/` directories with a `.gitkeep` each.

### Step 4 — Final report

End with this two-part recap. Use the `Status` enum: `created`, `already present`, `skipped`.

**Part 1 — outcome table.**

| Artifact | Status | Details |
|---|---|---|
| `dbt_project.yml` | … | profile = `<DBT_PROJECT_NAME>`, Snowflake adapter |
| `profiles.yml.example` | … | Snowflake |
| `README.md` | … | written |
| `.gitignore` | … | written |
| Model layout | … | `models/{input_ports,staging,intermediate,output_ports}/` |
| Output-port model YAML | … | `models/output_ports/<TABLE>.yml` (per-model, seeded with `ID` + `UPDATED_AT`) |
| Input-port sources stub | … | `models/input_ports/sources.yml` |
| Sample custom test | … | `tests/assert_updated_at_not_in_future.sql` |
| ODPS | … | `<DATA_PRODUCT_ID>.odps.yaml` |
| Output-port contract | … | `<CONTRACT_PATH>` (schema seeded with `ID` + `UPDATED_AT`) |
| `openlineage.yml` | … | transport URL omitted from the file; set at run time via `OPENLINEAGE__TRANSPORT__URL` env var |
| GitHub Actions workflow | … | `.github/workflows/data-product.yml` |

**Part 2 — next steps.** Bullet list:

- `uv venv && source .venv/bin/activate && uv pip install dbt-core dbt-snowflake openlineage-dbt datacontract-cli entropy-data`
- This demo assumes `~/.dbt/profiles.yml` already has a working Snowflake target. `profiles.yml.example` is checked in as a reference if you need to recreate the profile elsewhere; otherwise ignore it.
- Set `OPENLINEAGE__TRANSPORT__URL=<your-entropy-data-host>` and `OPENLINEAGE__TRANSPORT__AUTH__APIKEY=<your-entropy-data-api-key>` so `dbt-ol run` can publish lineage immediately. The committed `openlineage.yml` omits the URL on purpose so the same repo runs correctly against any deployment (cloud, self-hosted, local) — the URL comes from the env var. The `dataproduct-implement` skill handles this automatically by deriving both from the active `entropy-data connection`.
- `git init && git add . && git commit -m "Initial commit"`, then push to GitHub.
- Set GitHub repository secrets for the workflow: `ENTROPY_DATA_API_KEY`, `DBT_SNOWFLAKE_ACCOUNT`, `DBT_SNOWFLAKE_USER`, `DBT_SNOWFLAKE_PASSWORD`, `DBT_SNOWFLAKE_ROLE`, `DBT_SNOWFLAKE_WAREHOUSE`.
- Run **dataproduct-implement** next to generate models from a published data product, run dbt, run dbt + datacontract tests, and ship the first lineage event.

## Constraints

- **Snowflake-only.** This demo plugin intentionally drops platform branching. If the user asks for Databricks/BigQuery/Postgres, point them at the full builder at https://github.com/entropy-data/dataproduct-builder-dbt.
- **Greenfield only.** If `dbt_project.yml` exists, stop.
- **Do not run `dbt init`.** Use the templates here.
- **Do not commit secrets.** `profiles.yml` is in `.gitignore`; only `profiles.yml.example` is checked in.
- **Do not run `git init`, `git commit`, or `git push`** — surface them as next steps.
- **Idempotent.** Re-running on an already-populated directory is a no-op (refuse if anything would be overwritten).
