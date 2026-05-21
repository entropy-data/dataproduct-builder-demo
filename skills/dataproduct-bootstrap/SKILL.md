---
name: dataproduct-bootstrap
description: Bootstrap a brand-new Snowflake dbt data product from scratch in one go — dbt_project.yml, model layout, README, .gitignore, profiles.yml.example for Snowflake, ODPS, output-port ODCS, openlineage.yml, and a GitHub Actions workflow. Trigger when the user asks to start a new data product, scaffold a new dbt project, or "create a Snowflake data product from scratch."
---

# Bootstrap a new Snowflake dbt data product (demo)

Scaffold a Snowflake-only dbt data product following the Entropy Data conventions. Demo-grade: one batched question, one platform, no audits, no migration logic.

For populating the contract schema and dbt model bodies from a published data product, use the **dataproduct-implement** skill after this one.

## What this skill produces

After running, the directory contains:

```
.
├── dbt_project.yml
├── .gitignore
├── README.md
├── profiles.yml.example
├── <data-product-id>.odps.yaml
├── openlineage.yml
├── .github/workflows/data-product.yml
├── macros/
│   └── get_custom_schema.sql
└── models/
    ├── input_ports/_models.yml
    ├── staging/_models.yml
    ├── intermediate/_models.yml
    └── output_ports/v1/
        ├── _models.yml
        └── <contract-id>.odcs.yaml
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

Derive (matching the `dataproduct-builder-dbt` plugin's conventions, per the `dataproduct-dbt` skill):

- `DBT_PROJECT_NAME` = `DATA_PRODUCT_ID` — also the dbt profile name and the profile's fallback default schema. Staging + intermediate models override it to `internal_<DBT_PROJECT_NAME>` via `+schema:` in `dbt_project.yml`.
- `OUTPUT_PORT_NAME` = `DATA_PRODUCT_ID`
- `CONTRACT_ID` = `<DATA_PRODUCT_ID>-v1`
- `CONTRACT_FILE` = `<CONTRACT_ID>.odcs.yaml`
- `CONTRACT_PATH` = `models/output_ports/v1/<CONTRACT_FILE>`
- `ODPS_FILE` = `<DATA_PRODUCT_ID>.odps.yaml`
- `OUTPUT_PORT_SCHEMA` = `OP_<TABLE>_V1` (UPPERCASE) — the output-port schema in Snowflake, set literally by the `generate_schema_name` macro override in `macros/get_custom_schema.sql` (so it's NOT suffixed with the profile schema). Per dataproduct-builder-dbt's `dataproduct-dbt` convention the schema is `op_<output-port-id>_v<N>`; this demo plugin keys off `TABLE` because it scaffolds a single output port whose id equals the table name (matching the worked example in `dataproduct-dbt` SKILL.md: `op_customer_activity_v1`). This is the only public surface; internal staging/intermediate land in `INTERNAL_<DBT_PROJECT_NAME>`. The contract's `servers[].schema` and the platform's integration scan target this schema.

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
| `macros/get_custom_schema.sql` | `macros/get_custom_schema.sql` |
| `models/input_ports/_models.yml` | `models/input_ports/_models.yml` |
| `models/staging/_models.yml` | `models/staging/_models.yml` |
| `models/intermediate/_models.yml` | `models/intermediate/_models.yml` |
| `models/output_ports/v1/_models.yml` | `models/output_ports/v1/_models.yml` |
| `models/output_ports/v1/contract.odcs.yaml` | `<CONTRACT_PATH>` |
| `.github/workflows/data-product.yml` | `.github/workflows/data-product.yml` |

Also create empty `analyses/`, `macros/`, `seeds/`, `snapshots/`, `tests/` directories with a `.gitkeep` each.

### Step 4 — Final report

End with this two-part recap. Use the `Status` enum: `created`, `already present`, `skipped`.

**Part 1 — outcome table.**

| Artifact | Status | Details |
|---|---|---|
| `dbt_project.yml` | … | profile = `<DBT_PROJECT_NAME>`, Snowflake adapter |
| `profiles.yml.example` | … | Snowflake |
| `README.md` | … | written |
| `.gitignore` | … | written |
| Model layout | … | `models/{input_ports,staging,intermediate,output_ports/v1}/` |
| ODPS | … | `<DATA_PRODUCT_ID>.odps.yaml` |
| Output-port contract | … | `<CONTRACT_PATH>` (schema seeded with `id` + `updated_at`) |
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
