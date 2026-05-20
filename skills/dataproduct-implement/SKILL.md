---
name: dataproduct-implement
description: Given an Entropy Data data product URL or id, fetch its ODCS, generate Snowflake dbt models, run dbt-ol (ship lineage to Entropy Data on the spot), run dbt tests, and run datacontract tests — end-to-end in one go. Demo-grade. Trigger when the user asks to "implement the data product <url-or-id> [from its data contract]", "build a data product that implements its data contract", "build the dbt pipeline for this data product", "scaffold dbt models from a data contract", or any close variant referring to implementing, building, or materializing an existing published data product against its contract.
---

# Implement a data product from its data contract (demo)

Turn an Entropy Data data product into a working Snowflake dbt pipeline and prove it works — in one pass. The data contract (ODCS) is the source of truth for the output schema; this skill reads it, writes dbt artifacts that produce data matching the contract, runs everything against your Snowflake target, and ships an OpenLineage event so the pipeline shows up in Entropy Data immediately.

## When to use this vs. other skills

- **Empty directory, no dbt project yet** → run `dataproduct-bootstrap` first, then come back here.
- **Existing dbt project, want to derive Snowflake models from a published data contract and prove the pipeline works** → this skill.

## How to run this skill

> `${PLUGIN_ROOT}` below refers to the root of this plugin — the directory that contains `skills/`. On Claude Code it is set automatically as `${CLAUDE_PLUGIN_ROOT}`; use that. On any other agent (Codex, Copilot CLI, etc.) it is unset; resolve it as `../..` relative to **this `SKILL.md` file's directory** (i.e. the grandparent of `skills/<this-skill>/`).

> **Read every contract-specified value from the contract; never hardcode a
> literal.** Server name, schema, table, and types are read at run time from
> the data contract (e.g. `yq '.servers[0].server' <contract-file>`) — baking a
> fixed value into a command is a bug, even if it happens to match today. The
> data product id, when not supplied by the user, is the `id` in the local
> `*.odps.yaml`.

### Plan announcement (before Step 0)

Before running Step 0, print this plan to the user verbatim:

> Running **dataproduct-implement**. I'll:
> 1. Pre-checks: confirm this is a dbt project; `dbt`, `dbt-ol`, `datacontract`, `entropy-data`, `jq`, and `yq` are on PATH; the Entropy Data API key is available from `entropy-data connection`; Snowflake credentials are readable from `~/.dbt/profiles.yml`.
> 2. Resolve the data product by id (`entropy-data dataproducts get <id>`).
> 3. Fetch each output port's data contract (`entropy-data datacontracts get`) and save it to `datacontracts/`. Remote contract is the source of truth — local file is always overwritten.
> 4. Translate the ODCS schema into dbt models: append missing column projections to `models/output_ports/<table>.sql`, missing column entries to `<table>.yml`. Existing SQL and tests are preserved byte-identical.
> 5. Wire input ports from active access agreements, write sources, project columns 1:1, leave the rest as TODOs.
> 6. Run `dbt parse` to catch syntax errors.
> 7. Run `dbt-ol run` against the user's Snowflake target — this builds the tables AND ships the lineage event to Entropy Data on the spot.
> 8. Run `dbt test` against the same target.
> 9. Run `datacontract test` against each output-port contract.
> 10. Stamp the data product on Entropy Data with the `dataProductBuilder` customProperty.
> 11. Trigger a Snowflake re-ingest so the platform's asset inventory picks up the new tables (`entropy-data integrations run`).
> 12. Summarize what was generated, what ran, and what's still TODO.

Then proceed.

### Step 0 — Pre-checks

- Confirm `dbt_project.yml` exists at the working directory root. If not, route the user to `dataproduct-bootstrap` and stop.
- **Set up (or refresh) the project-local venv with the full toolchain.** This is idempotent — `uv pip install` is a no-op when the dependency is already satisfied:

  ```bash
  [ -d .venv ] || uv venv
  source .venv/bin/activate
  uv pip install --quiet dbt-core dbt-snowflake openlineage-dbt 'datacontract-cli[snowflake]' entropy-data
  ```

  **Activate the venv before every bash call in subsequent steps** — shell state doesn't carry between bash invocations. Don't fall back to `uv tool install` for individual binaries; `dbt`, `dbt-ol`, and `datacontract` must share a single Python env so the Snowflake adapter is visible to all three.
- Confirm `entropy-data connection test` succeeds. Otherwise stop and tell the user to run `entropy-data connection add <name> --host <host> --api-key <key>`.
- Confirm `jq` and `yq` are on PATH (system binaries, not pip-installed). Otherwise stop with `brew install jq yq` (macOS) or the apt equivalent.
- Assume the user has a working Snowflake dbt profile. Don't audit `~/.dbt/profiles.yml`; if it's misconfigured, `dbt parse` / `dbt-ol run` will surface a clear error.

### Step 1 — Resolve the data product

Resolve `DATA_PRODUCT_ID`: if the user gave a full URL (`https://app.entropy-data.com/<org>/dataproducts/<id>`) take the trailing id; if they gave a bare id use it; otherwise read `.id` from the single `*.odps.yaml` in the working directory (`yq '.id' *.odps.yaml`). If none of these yields an id, ask the user.

Load the data product ODPS via the `entropy-data` CLI: run `entropy-data dataproducts get "$DATA_PRODUCT_ID" -o yaml`. Remember the response as `DATA_PRODUCT`. Extract:

- `DATA_PRODUCT_ID`, `DATA_PRODUCT_NAME`, owning team, purpose
- the list of output ports — each has an id, a server (database/schema/table), and a linked data contract id

Always use the `entropy-data` CLI for any connection to Entropy Data (data products, data contracts, access, publishing). Do not use the Entropy Data MCP server for these calls.

If the data product has more than one output port, ask the user which one(s) to implement. Default to all.

If the data product does not exist on Entropy Data, stop and ask the user whether to create it via `dataproduct-bootstrap` first. This demo skill does not create platform records itself.

### Step 2 — Fetch the data contract

For each selected output port: `entropy-data datacontracts get <contract-id> -o yaml`, written to `datacontracts/<table>_v<N>.odcs.yaml` (snake-case `name` from `schema[0]`, major version, default `v1`). Layout follows the [Building Data Products with dbt guide](https://www.entropy-data.com/learn/data-products-with-dbt). Remember as `CONTRACT`.

**Always overwrite the local file with the remote response.** The remote contract is the spec; the local SQL is the implementation. A divergence is the whole point of the run — someone changed the contract and the implementation needs to catch up. (Step 3 appends column projections to the existing SQL without touching CTEs / joins / filters, so the implementation logic is safe.)

From `CONTRACT` you'll need `schema` (table + properties: `logicalType`, `required`, `primaryKey`, `unique`, `description`, `classification`) and `servers` (Snowflake server the contract test runs against).

### Step 3 — Translate ODCS schema to dbt artifacts

**Output column identifier rule (applies to every property in this step and Step 4).** For every contract property, resolve `OUT_COL = property.physicalName // property.name` — prefer `physicalName` when present, fall back to `name`. Use `OUT_COL` for the SQL alias **and** the `<table>.yml` `columns: - name:` entry so the projected column, the dbt tests, and the materialized warehouse column all agree with what the contract declares. If `OUT_COL` is not already all-uppercase, double-quote it in the SQL alias (`as "MixedCase"`) so Snowflake preserves it verbatim instead of folding to uppercase. This keeps the dbt side (projected column, tests, materialized column) aligned with the contract's `physicalName`. `datacontract test` resolves each field by `physicalName` when set (ODCS standard), so a contract whose logical `name` differs from its `physicalName` — e.g. a semantic concept `name: brand` with `physicalName: BRAND` — tests correctly against the physical column.

For each contract:

1. Decide the dbt-side table name. Default: the `schema[0].name` from the contract. Confirm with the user if it differs from the output port's server table.
2. **Identify candidate input ports.** Run `entropy-data access list --consumer-dataproduct <DATA_PRODUCT_ID> -o json` to list active access agreements. Each entry's `provider.dataProductId` / `provider.outputPortId` is an input port this product can read. Keep agreements with `info.active: true`; ignore `pending` / `rejected`. If `models/input_ports/<provider-output-port-id>.source.yaml` already exists for an agreement, treat it as authoritative.
3. Generate or update `models/output_ports/<table>.sql`. The file may already exist with non-trivial business logic — CTEs, joins, window functions — **never rewrite it**. Only two edits are allowed:
   - **File doesn't exist** → create a stub `select` that projects each contract column as `cast(... as <snowflake-type>) as <OUT_COL>` (`OUT_COL` per the rule above); leave the `from` clause as a TODO citing the candidate input ports from Step 3.2.
   - **File exists** → in the final `select` block, **append** `cast(... as <type>) as <OUT_COL>` for every contract column not already projected, in contract order, fixing the trailing comma. Everything else (CTEs, joins, filters, existing projections) stays byte-identical.

   The file must start with:

   ```sql
   {{ config(materialized='table', schema='op_v1') }}

   -- Governed by <contract-file>.odcs.yaml (ODCS id: <CONTRACT_ID>)
   ```

   `schema='op_v1'` separates the output table from staging/intermediate models — dbt concatenates this with the profile's default schema (per [the guide](https://www.entropy-data.com/learn/data-products-with-dbt)) so the materialized schema name matches the contract's `servers[].schema`.

4. Generate or update `models/output_ports/<table>.yml` — one YAML file per model. New file → create with the structure below. Existing file → append `columns:` entries for contract columns not already listed; leave existing entries alone.

   ```yaml
   version: 2

   models:
     - name: <table>
       description: <from contract>
       config:
         meta:
           data_contract:
             id: <CONTRACT_ID>
             file: datacontracts/<table>_v<N>.odcs.yaml
           owner: <team>
         materialized: table
         contract:
           enforced: true
       columns:
         - name: <col>
           description: <from contract>
           data_type: <UPPERCASE Snowflake type>
           constraints:
             - type: not_null   # required: true
             - type: unique     # unique: true or primaryKey: true
   ```

   ODCS → dbt: `required: true` → `not_null` constraint, `unique: true` or `primaryKey: true` → `unique` + `not_null` constraints, `enum` → `accepted_values` (under `data_tests:`, not `constraints:`).

5. Map ODCS `logicalType` to Snowflake types:

| ODCS `logicalType` | Snowflake |
|---|---|
| `string`/`text` | `varchar` |
| `integer`/`long` | `number` |
| `decimal`/`numeric` | `number(38,9)` |
| `boolean` | `boolean` |
| `timestamp` | `timestamp_ntz` |
| `date` | `date` |

### Step 4 — Wire input ports and project columns

For each output port:

1. **Declare each candidate input port as a dbt source** — for every access agreement from Step 3.2:
   1. Fetch the provider data product (`entropy-data dataproducts get <provider-data-product-id> -o yaml`) to resolve the server (database/schema/table) and linked contract id.
   2. Fetch the upstream contract (`entropy-data datacontracts get <provider-contract-id> -o yaml`) and write it to `models/input_ports/<provider-output-port-id>.odcs.yaml` as a trust snapshot.
   3. Write `models/input_ports/<provider-output-port-id>.source.yaml`:

      ```yaml
      version: 2
      sources:
        - name: <provider-data-product-id>_<provider-output-port-id>
          database: <database>
          schema: <schema>
          config:
            meta:
              data_contract:
                id: <provider-contract-id>
                file: models/input_ports/<provider-output-port-id>.odcs.yaml
          tables:
            - name: <table>
              description: <from contract>
              columns:
                - name: <col>
                  description: <from contract>
                  data_type: <snowflake type from the type map in Step 3>
      ```

   One pair (`*.odcs.yaml` + `*.source.yaml`) per agreement. Surface diffs and ask before overwriting an existing file.

2. **Match input columns to output columns** by name — comparing against both the input property's `name` and its `physicalName` — or an obvious synonym only if the input contract's description makes it explicit. For each output column, if exactly one input has a matching column, project `cast(<input_col> as <snowflake_type>) as <OUT_COL>` (`OUT_COL` per the output column identifier rule in Step 3). Otherwise leave `null as <OUT_COL>` with a `-- TODO:` comment.

3. **Write the SQL body.**
   - **Single input source, columns match 1:1** → replace the TODO `from` with `from {{ source('<provider-data-product-id>_<provider-output-port-id>', '<table>') }}`.
   - **Multiple input sources** → leave the join logic as an inline TODO listing each candidate `{{ source(...) }}` and the join keys.
   - **Derived / aggregated columns** → leave as `null as <col>` with a `-- TODO: compute <description>` comment.

### Step 5 — `dbt parse`

Run `dbt parse`. If it fails, surface the error, fix obvious mistakes (wrong source name, typos in `<table>.yml`), and re-run. Do not proceed to Step 6 with a failing parse.

### Step 6 — `dbt-ol run` (this is where lineage gets shipped)

Confirm with the user: "Run `dbt-ol run` against your Snowflake target now? This materializes the models in Snowflake and ships the lineage event to Entropy Data immediately." Wait for explicit yes.

If the user has TODOs left in any output-port model (unwired `from`, derived columns, multi-source joins), warn them that the run will fail those models. Offer to scope to only the models with no TODOs: `dbt-ol run --select <wired-model-1> <wired-model-2>`.

Run with both OpenLineage env vars derived inline from the active `entropy-data connection` (target inferred from `dbt_project.yml`'s `profile:` — usually `dev` locally):

```
OPENLINEAGE__TRANSPORT__URL=$(entropy-data connection get -o json | jq -r .host) \
OPENLINEAGE__TRANSPORT__AUTH__APIKEY=$(entropy-data connection get -o json | jq -r .api_key) \
  dbt-ol run --target <target>
```

**Both env vars must be set on the same command.** The committed `openlineage.yml` intentionally omits `url:`, so a run with only `__APIKEY` fails with `RuntimeError: 'url' key not passed to HttpConfig` before dbt even starts. The fix is to add `__URL` back to the *same* invocation, not to retry with just `__URL` set.

Capture stdout and exit code. Non-zero means at least one model failed; surface the dbt log section, do not retry silently.

If `dbt-ol run` succeeded, **the data product is now visible with materialized tables AND a lineage event in Entropy Data.** Tell the user this explicitly in the final report — it is the whole point of the demo.

### Step 7 — `dbt test`

```
dbt test --target <target>
```

Captures the contract-derived tests (`not_null`, `unique`, `accepted_values`) added in Step 3. Surface failures by model and test name.

### Step 8 — `datacontract test`

For each output-port contract, derive the Snowflake credentials from the dbt profile inline — don't require the user to set `DATACONTRACT_SNOWFLAKE_*` in their shell:

```
CONTRACT_FILE=datacontracts/<table>_v<N>.odcs.yaml
SERVER=$(yq '.servers[0].server' "$CONTRACT_FILE")          # from the contract — never a hardcoded literal
PROFILE=$(yq '.profile' dbt_project.yml)
TARGET=$(yq ".${PROFILE}.target" ~/.dbt/profiles.yml)   # or the --target passed earlier
DATACONTRACT_SNOWFLAKE_USERNAME=$(yq ".${PROFILE}.outputs.${TARGET}.user"     ~/.dbt/profiles.yml) \
DATACONTRACT_SNOWFLAKE_PASSWORD=$(yq ".${PROFILE}.outputs.${TARGET}.password" ~/.dbt/profiles.yml) \
DATACONTRACT_SNOWFLAKE_ROLE=$(yq     ".${PROFILE}.outputs.${TARGET}.role"     ~/.dbt/profiles.yml) \
DATACONTRACT_SNOWFLAKE_WAREHOUSE=$(yq ".${PROFILE}.outputs.${TARGET}.warehouse" ~/.dbt/profiles.yml) \
  datacontract test "$CONTRACT_FILE" --server "$SERVER" --logs
```

`--logs` ensures the failure detail (field + rule) is in stdout. Non-zero exit means at least one rule failed. Capture per-contract result for the final report.

### Step 9 — Stamp the data product as builder-managed

Check `DATA_PRODUCT.customProperties` for an entry `property: "dataProductBuilder"` with `value: "https://github.com/entropy-data/dataproduct-builder-demo"`. If already present, skip.

Otherwise:

1. `entropy-data dataproducts get <DATA_PRODUCT_ID> -o yaml > /tmp/<DATA_PRODUCT_ID>.odps.yaml`
2. Append to the top-level `customProperties`:

   ```yaml
   customProperties:
     - property: "dataProductBuilder"
       value: "https://github.com/entropy-data/dataproduct-builder-demo"
   ```

3. `entropy-data dataproducts put <DATA_PRODUCT_ID> --file /tmp/<DATA_PRODUCT_ID>.odps.yaml`
4. Delete the temp file.

### Step 10 — Refresh the platform's asset inventory

The Entropy Data platform sees a Snowflake table only after its Snowflake integration ingests the schema. Until the next ingestion, the table dbt just materialized doesn't show up under the data product, and the schema-drift warning on the data contract page won't clear. Trigger a manual run so the inventory catches up.

The integration to trigger is the one that scans the output port's database. Find it:

```bash
entropy-data integrations list --source snowflake -o json \
  | jq '.[] | {ingestionId, externalId, name}'
```

If exactly one Snowflake integration is configured (the common case on demo orgs), grab its `externalId` and trigger it:

```bash
entropy-data integrations run <externalId>
```

The call returns immediately with a `scheduledAt` timestamp (202). The ingestion runs in the background — typically a few minutes on a small Snowflake account, longer on larger ones. Don't pass `--wait` from this skill; the ingest is not on the critical path for the demo, and waiting would block the final report.

If the listing returns multiple Snowflake integrations, match the one whose `assetOwnerTeamExternalId` equals the data product's team external id; if still ambiguous, ask the user to pick and re-run with that `externalId`. If none are configured, skip this step entirely and call it out in the final report — the data product still works; the asset inventory just lags until the next scheduled run.

If the call returns 409 (`already_running`), don't try to cancel — note it in the final report ("re-ingest already in flight") and continue.

### Step 11 — Final report

End with this two-part recap. Use the `Status` enum: `created`, `updated`, `already present`, `passed`, `failed`, `skipped`.

**Part 1 — outcome table.**

| Artifact | Status | Details |
|---|---|---|
| Data product | already present | `<DATA_PRODUCT_ID>` |
| `dataProductBuilder` customProperty | … | "added" / "already present" |
| Output-port data contract `<CONTRACT_ID>` | … | `datacontracts/<table>_v<N>.odcs.yaml` |
| Input-port contracts | … | `<N>` files at `models/input_ports/<...>.odcs.yaml` |
| Input-port sources | … | `<N>` files at `models/input_ports/<...>.source.yaml` |
| Model `<table>.sql` | … | "wired to `<source>`" / "join TODO" / "skipped per user" |
| `<table>.yml` columns added | … | counts (only columns newly appended from the contract; existing columns untouched) |
| `dbt parse` | … | passed / failed: `<reason>` |
| `dbt-ol run` | … | "passed — N models materialized, lineage shipped to `<API_HOST>`" / "failed" / "skipped" |
| `dbt test` | … | "passed — N tests" / "failed: N of M" / "skipped" |
| `datacontract test` | … | per contract: "passed" / "failed: <count>" / "skipped" |
| Snowflake re-ingest | … | "triggered: `<integration-externalId>`" / "already running" / "skipped: no Snowflake integration" |

**Part 2 — next steps.** Bullet list, only what applies:

- For each model with a join or derived-column TODO, name the inputs and the missing logic.
- For each `failed` row, the concrete next action (which model, which test, which contract rule).
- If `dbt-ol run` succeeded, link the user to `<API_HOST>/dataproducts/<DATA_PRODUCT_ID>` so they can see the lineage event land.
- If GitHub Actions are set up, remind the user to set the workflow secrets (`ENTROPY_DATA_API_KEY`, `DBT_SNOWFLAKE_*`) so the CI run reproduces the local run.

If everything passed and there are no TODOs, write: `Pipeline implemented, materialized, tested, and lineage published. Nothing else to do.`

## Constraints

- **Snowflake only.** The type map, profiles, and CLI invocations are Snowflake-specific. If the user's profile is not Snowflake, stop.
- **Contract is source of truth for schema, not logic.** Columns / types / tests come from the contract; joins, aggregations, and derivations stay in the user's SQL.
- **Don't auto-fix failing dbt or datacontract tests.** Report them; the fix belongs to the user.
- **Don't push or commit.** Leave VCS state to the user.
- **Idempotent.** Re-running on the same data product when files already match the contract is a no-op (except the run/test commands, which always re-execute).
