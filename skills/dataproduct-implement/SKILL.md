---
name: dataproduct-implement
description: Given an Entropy Data data product URL or id, fetch its ODCS, generate Snowflake dbt models, run dbt-ol (ship lineage to Entropy Data on the spot), run dbt tests, and run datacontract tests — end-to-end in one go. Demo-grade. Trigger when the user asks to "implement the data product <url>", "build the dbt pipeline for this data product", or "scaffold dbt models from a data contract".
---

# Implement a data product from its data contract (demo)

Turn an Entropy Data data product into a working Snowflake dbt pipeline and prove it works — in one pass. The data contract (ODCS) is the source of truth for the output schema; this skill reads it, writes dbt artifacts that produce data matching the contract, runs everything against your Snowflake target, and ships an OpenLineage event so the pipeline shows up in Entropy Data immediately.

## When to use this vs. other skills

- **Empty directory, no dbt project yet** → run `dataproduct-bootstrap` first, then come back here.
- **Existing dbt project, want to derive Snowflake models from a published data contract and prove the pipeline works** → this skill.

## How to run this skill

> `${PLUGIN_ROOT}` below refers to the root of this plugin — the directory that contains `skills/`. On Claude Code it is set automatically as `${CLAUDE_PLUGIN_ROOT}`; use that. On any other agent (Codex, Copilot CLI, etc.) it is unset; resolve it as `../..` relative to **this `SKILL.md` file's directory** (i.e. the grandparent of `skills/<this-skill>/`).

### Plan announcement (before Step 0)

Before running Step 0, print this plan to the user verbatim:

> Running **dataproduct-implement**. I'll:
> 1. Pre-checks: confirm this is a dbt project; `dbt`, `dbt-ol`, `datacontract`, `entropy-data`, `jq`, and `yq` are on PATH; the Entropy Data API key is available from `entropy-data connection`; Snowflake credentials are readable from `~/.dbt/profiles.yml`.
> 2. Resolve the data product by id (`entropy-data dataproducts get <id>`).
> 3. Fetch each output port's data contract (`entropy-data datacontracts get`) and save it to `models/output_ports/v<N>/`.
> 4. Translate the ODCS schema into dbt models: SQL column projections + `_models.yml` tests.
> 5. Wire input ports from active access agreements, write sources, project columns 1:1, leave the rest as TODOs.
> 6. Run `dbt parse` to catch syntax errors.
> 7. Run `dbt-ol run` against the user's Snowflake target — this builds the tables AND ships the lineage event to Entropy Data on the spot.
> 8. Run `dbt test` against the same target.
> 9. Run `datacontract test` against each output-port contract.
> 10. Stamp the data product on Entropy Data with the `dataProductBuilder` customProperty.
> 11. Summarize what was generated, what ran, and what's still TODO.

Then proceed.

### Step 0 — Pre-checks

- Confirm `dbt_project.yml` exists at the working directory root. If not, route the user to `dataproduct-bootstrap` and stop.
- Confirm `dbt --version`, `dbt-ol --version`, `datacontract --version`, and `entropy-data --version` are on PATH. If any are missing, surface the install line (`uv pip install dbt-core dbt-snowflake openlineage-dbt 'datacontract-cli[snowflake]' entropy-data`) and stop. Also confirm `jq` and `yq` are on PATH — they are used to derive credentials below.
- Confirm `entropy-data connection test` succeeds. If not, stop and tell the user to run `entropy-data connection add <name> --host <host> --api-key <key>`.
- **Assume the user has a working Snowflake dbt profile.** Do not audit `~/.dbt/profiles.yml` for correctness; if it is misconfigured, `dbt parse` / `dbt-ol run` will surface a clear error and the user can fix it then.
- **Derive runtime credentials from existing config — do not require the user to export env vars.** Resolve them once here and reuse them inline in Step 6 / Step 8:
  - `OPENLINEAGE__TRANSPORT__AUTH__APIKEY` ← `entropy-data connection get -o json | jq -r .apiKey` (the active connection's API key).
  - `DATACONTRACT_SNOWFLAKE_USERNAME` / `_PASSWORD` / `_ROLE` / `_WAREHOUSE` ← `~/.dbt/profiles.yml`. The profile is `yq '.profile' dbt_project.yml`; the target is the profile's `target:` (or the explicit `--target` you'll pass to dbt); read `user` / `password` / `role` / `warehouse` from `outputs.<target>`.
  If a value is genuinely missing from both sources (e.g. the connection has no `apiKey`, or the dbt profile is missing `password`), stop and tell the user which source to fix. Do not echo or persist these values; export them only as part of the command invocation that needs them.

### Step 1 — Resolve the data product

Accept either a full URL (`https://app.entropy-data.com/<org>/dataproducts/<id>`, extract the trailing id) or a bare id.

Load the data product ODPS via the `entropy-data` CLI: run `entropy-data dataproducts get <id> -o yaml`. Remember the response as `DATA_PRODUCT`. Extract:

- `DATA_PRODUCT_ID`, `DATA_PRODUCT_NAME`, owning team, purpose
- the list of output ports — each has an id, a server (database/schema/table), and a linked data contract id

Always use the `entropy-data` CLI for any connection to Entropy Data (data products, data contracts, access, publishing). Do not use the Entropy Data MCP server for these calls.

If the data product has more than one output port, ask the user which one(s) to implement. Default to all.

If the data product does not exist on Entropy Data, stop and ask the user whether to create it via `dataproduct-bootstrap` first. This demo skill does not create platform records itself.

### Step 2 — Fetch the data contract

For each selected output port, run `entropy-data datacontracts get <contract-id> -o yaml`. Remember as `CONTRACT`, write it to `models/output_ports/v<N>/<contract-id>.odcs.yaml` (default `v1` if the output port does not declare a version). If the file already exists and differs, surface the diff and ask before overwriting.

You need from `CONTRACT`:

- `schema` (table name → properties list with `logicalType`, `required`, `primaryKey`, `unique`, `description`, `classification`)
- `servers` (the Snowflake server the contract test will run against)

### Step 3 — Translate ODCS schema to dbt artifacts

**Output column identifier rule (applies to every property in this step and Step 4).** For every contract property, resolve `OUT_COL = property.physicalName // property.name` — prefer `physicalName` when present, fall back to `name`. Use `OUT_COL` for the SQL alias **and** the `_models.yml` `columns: - name:` entry so the projected column, the dbt tests, and the materialized warehouse column all agree with what the contract declares. If `OUT_COL` is not already all-uppercase, double-quote it in the SQL alias (`as "MixedCase"`) so Snowflake preserves it verbatim instead of folding to uppercase. Note: this keeps the dbt side internally consistent; `datacontract test` keys its presence check on the contract field `name`, so a contract whose `name` and `physicalName` disagree in case is still an upstream contract bug to fix at the source.

For each contract:

1. Decide the dbt-side table name. Default: the `schema[0].name` from the contract. Confirm with the user if it differs from the output port's server table.
2. **Identify candidate input ports.** Run `entropy-data access list --consumer-dataproduct <DATA_PRODUCT_ID> -o json` to list active access agreements. Each entry's `provider.dataProductId` / `provider.outputPortId` is an input port this product can read. Keep agreements with `info.active: true`; ignore `pending` / `rejected`. If `models/input_ports/<provider-output-port-id>.source.yaml` already exists for an agreement, treat it as authoritative.
3. Generate `models/output_ports/v1/<table>.sql` — a stub `select` that projects each contract column with `cast(... as <snowflake-type>) as <OUT_COL>` (`OUT_COL` per the output column identifier rule above). Leave the `from` clause as a TODO commented with the candidate input ports from Step 3.2. Prepend a one-line header comment:

   ```sql
   -- Governed by <contract-file>.odcs.yaml (ODCS id: <CONTRACT_ID>)
   ```

4. Append the model to `models/output_ports/v1/_models.yml`:

   ```yaml
   models:
     - name: <table>
       description: <from contract>
       meta:
         data_contract:
           id: <CONTRACT_ID>
           file: models/output_ports/v1/<contract-file>.odcs.yaml
       columns:
         - name: <col>
           description: <from contract>
           data_tests: [not_null]   # only when required or primaryKey
   ```

   Translate ODCS rules to dbt tests: `required: true` → `not_null`, `unique: true` or `primaryKey: true` → `unique` (+ `not_null`), enum → `accepted_values`.

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

Run `dbt parse`. If it fails, surface the error, fix obvious mistakes (wrong source name, typos in `_models.yml`), and re-run. Do not proceed to Step 6 with a failing parse.

### Step 6 — `dbt-ol run` (this is where lineage gets shipped)

Confirm with the user: "Run `dbt-ol run` against your Snowflake target now? This materializes the models in Snowflake and ships the lineage event to Entropy Data immediately." Wait for explicit yes.

If the user has TODOs left in any output-port model (unwired `from`, derived columns, multi-source joins), warn them that the run will fail those models. Offer to scope to only the models with no TODOs: `dbt-ol run --select <wired-model-1> <wired-model-2>`.

Command (default target inferred from `dbt_project.yml`'s `profile:` block — usually `dev` for local runs). Export the OpenLineage API key inline by reading it from the entropy-data CLI connection (resolved in Step 0); do not require the user to have it in their shell:

```
OPENLINEAGE__TRANSPORT__AUTH__APIKEY=$(entropy-data connection get -o json | jq -r .apiKey) \
  dbt-ol run --target <target>
```

This is the Entropy Data API key the lineage transport in `openlineage.yml` uses to authenticate.

Capture stdout and exit code. Non-zero means at least one model failed; surface the dbt log section, do not retry silently.

If `dbt-ol run` succeeded, **the data product is now visible with materialized tables AND a lineage event in Entropy Data.** Tell the user this explicitly in the final report — it is the whole point of the demo.

### Step 7 — `dbt test`

```
dbt test --target <target>
```

Captures the contract-derived tests (`not_null`, `unique`, `accepted_values`) added in Step 3. Surface failures by model and test name.

### Step 8 — `datacontract test`

For each output-port contract, derive the Snowflake credentials from the dbt profile (as resolved in Step 0) and export them inline — do not require the user to set `DATACONTRACT_SNOWFLAKE_*` in their shell:

```
PROFILE=$(yq '.profile' dbt_project.yml)
TARGET=$(yq ".${PROFILE}.target" ~/.dbt/profiles.yml)   # or the --target passed earlier
DATACONTRACT_SNOWFLAKE_USERNAME=$(yq ".${PROFILE}.outputs.${TARGET}.user"     ~/.dbt/profiles.yml) \
DATACONTRACT_SNOWFLAKE_PASSWORD=$(yq ".${PROFILE}.outputs.${TARGET}.password" ~/.dbt/profiles.yml) \
DATACONTRACT_SNOWFLAKE_ROLE=$(yq     ".${PROFILE}.outputs.${TARGET}.role"     ~/.dbt/profiles.yml) \
DATACONTRACT_SNOWFLAKE_WAREHOUSE=$(yq ".${PROFILE}.outputs.${TARGET}.warehouse" ~/.dbt/profiles.yml) \
  datacontract test models/output_ports/v<N>/<contract-id>.odcs.yaml --server production --logs
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

### Step 10 — Final report

End with this two-part recap. Use the `Status` enum: `created`, `updated`, `already present`, `passed`, `failed`, `skipped`.

**Part 1 — outcome table.**

| Artifact | Status | Details |
|---|---|---|
| Data product | already present | `<DATA_PRODUCT_ID>` |
| `dataProductBuilder` customProperty | … | "added" / "already present" |
| Output-port data contract `<CONTRACT_ID>` | … | `models/output_ports/v<N>/<contract-id>.odcs.yaml` |
| Input-port contracts | … | `<N>` files at `models/input_ports/<...>.odcs.yaml` |
| Input-port sources | … | `<N>` files at `models/input_ports/<...>.source.yaml` |
| Model `<table>.sql` | … | "wired to `<source>`" / "join TODO" / "skipped per user" |
| `_models.yml` entries | … | counts |
| `dbt parse` | … | passed / failed: `<reason>` |
| `dbt-ol run` | … | "passed — N models materialized, lineage shipped to `<API_HOST>`" / "failed" / "skipped" |
| `dbt test` | … | "passed — N tests" / "failed: N of M" / "skipped" |
| `datacontract test` | … | per contract: "passed" / "failed: <count>" / "skipped" |

**Part 2 — next steps.** Bullet list, only what applies:

- For each model with a join or derived-column TODO, name the inputs and the missing logic.
- For each `failed` row, the concrete next action (which model, which test, which contract rule).
- If `dbt-ol run` succeeded, link the user to `<API_HOST>/dataproducts/<DATA_PRODUCT_ID>` so they can see the lineage event land.
- If GitHub Actions are set up, remind the user to set the workflow secrets (`ENTROPY_DATA_API_KEY`, `DBT_SNOWFLAKE_*`) so the CI run reproduces the local run.

If everything passed and there are no TODOs, write: `Pipeline implemented, materialized, tested, and lineage published. Nothing else to do.`

## Constraints

- **Snowflake only.** The type map, profiles, and CLI invocations are Snowflake-specific. If the user's profile is not Snowflake, stop.
- **Contract is source of truth for schema, not logic.** Generate columns, types, and tests from the contract. Project and cast in SQL only — do not invent joins, aggregations, or column derivations.
- **Don't overwrite existing dbt SQL silently.** Surface the diff and ask.
- **Don't auto-fix failing dbt or datacontract tests.** Report them; the fix belongs to the user.
- **Don't push or commit.** Leave VCS state to the user.
- **Idempotent.** Re-running on the same data product when files already match the contract is a no-op (except the run/test commands, which always re-execute).
