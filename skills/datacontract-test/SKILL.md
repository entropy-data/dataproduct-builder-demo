---
name: datacontract-test
description: >-
  Run `datacontract test` against ODCS contracts in the project to verify the live Snowflake
  data still conforms to schema, quality rules, and freshness. Handles two kinds of contracts
  with different semantics: output-port contracts under `datacontracts/*.odcs.yaml` (tested
  against this project's Snowflake — "am I still producing what I promised?") and input-port
  contracts under `models/input_ports/*.odcs.yaml` (tested against the upstream Snowflake
  server — "is upstream still producing what I trusted?"). Trigger when the user asks to
  "test the data contracts", "verify the data product matches its contract", "are we still
  contract-conformant", "check upstream drift", or "run the contract tests".
---

# Test ODCS data contracts against Snowflake

Run the **Data Contract CLI** (`datacontract test`) against contracts in the project to check whether the data currently in Snowflake still matches the schema and quality rules declared in the contract.

Two kinds of contracts live in this project and they test against different Snowflake servers:

- **Output-port contracts** at `datacontracts/*.odcs.yaml` — what this data product commits to produce. They test against **this project's** Snowflake target. A failure means we are no longer producing what we promised. Layout matches the [Building Data Products with dbt](https://www.entropy-data.com/learn/data-products-with-dbt) guide.
- **Input-port contracts** at `models/input_ports/*.odcs.yaml` — cached snapshots of what we trust upstream to produce, written by `dataproduct-implement` per active access agreement. They test against the **upstream provider's** Snowflake server, using the server block from the upstream ODCS. A failure means upstream drifted from the contract we trusted; the consequence is that our output may break too. Treat input-port failures as an upstream incident, not a local bug.

## When to use this vs. other skills

- **Just ran `dataproduct-implement` and want to re-test without re-running dbt** → this skill.
- **A CI run failed the contract test step** → this skill, to reproduce locally with `--logs`.
- **You want to edit a contract and check the impact** → not in this demo plugin; use [datacontract-edit](https://github.com/entropy-data/dataproduct-builder-dbt/blob/main/skills/datacontract-edit/SKILL.md) from the full builder.

## How to run this skill

> `${PLUGIN_ROOT}` below refers to the root of this plugin — the directory that contains `skills/`. On Claude Code it is set automatically as `${CLAUDE_PLUGIN_ROOT}`; use that. On any other agent (Codex, Copilot CLI, etc.) it is unset; resolve it as `../..` relative to **this `SKILL.md` file's directory** (i.e. the grandparent of `skills/<this-skill>/`).

### Plan announcement (before Step 0)

Before running Step 0, print this plan to the user verbatim:

> Running **datacontract-test**. I'll:
> 1. Pre-checks: confirm `datacontract` is on PATH; for output-port contracts auto-source Snowflake credentials from `~/.dbt/profiles.yml`; for input-port contracts require `DATACONTRACT_SNOWFLAKE_*` env vars.
> 2. Pick which contract(s) to test — defaults to all `datacontracts/*.odcs.yaml` and `models/input_ports/*.odcs.yaml`.
> 3. Pick the server (defaults to `production` if the contract defines one).
> 4. Run `datacontract test` per contract and capture the result.
> 5. Report pass/fail with per-rule detail; flag missing credentials separately from real failures.

Then proceed.

### Step 0 — Pre-checks

- Confirm `datacontract --version` is on PATH. If not, stop and tell the user to install it: `uv tool install 'datacontract-cli[snowflake]'`.
- Confirm at least one `*.odcs.yaml` exists under `datacontracts/` or `models/input_ports/`. If not, stop and tell the user there is nothing to test.
- Confirm Snowflake credentials for the Data Contract CLI. The CLI reads `DATACONTRACT_SNOWFLAKE_*` env vars; **for output-port contracts** this skill mirrors `dataproduct-implement` and derives them inline from `~/.dbt/profiles.yml` at run time (Step 3), so the user does not need to export them manually:

  ```bash
  PROFILE=$(yq '.profile' dbt_project.yml)
  TARGET=$(yq ".${PROFILE}.target" ~/.dbt/profiles.yml)
  # then for each datacontract test invocation:
  DATACONTRACT_SNOWFLAKE_USERNAME=$(yq ".${PROFILE}.outputs.${TARGET}.user"     ~/.dbt/profiles.yml) \
  DATACONTRACT_SNOWFLAKE_PASSWORD=$(yq ".${PROFILE}.outputs.${TARGET}.password" ~/.dbt/profiles.yml) \
  DATACONTRACT_SNOWFLAKE_ROLE=$(yq     ".${PROFILE}.outputs.${TARGET}.role"     ~/.dbt/profiles.yml) \
  DATACONTRACT_SNOWFLAKE_WAREHOUSE=$(yq ".${PROFILE}.outputs.${TARGET}.warehouse" ~/.dbt/profiles.yml) \
    datacontract test …
  ```

  **For input-port contracts** the upstream server is a different Snowflake account, so creds cannot come from the local dbt profile. Require explicit env vars:

  ```bash
  DATACONTRACT_SNOWFLAKE_USERNAME
  DATACONTRACT_SNOWFLAKE_PASSWORD       # or use JWT / SSO (see below)
  DATACONTRACT_SNOWFLAKE_ROLE
  DATACONTRACT_SNOWFLAKE_WAREHOUSE
  ```

  If those are unset when an input-port contract is in scope, list them and ask whether to skip just the input-port contracts or stop entirely. Do not try to source upstream credentials from anywhere outside the environment.

### Step 1 — Select contracts

- If the user named a specific contract file or data product id, resolve it to one file. Search both `datacontracts/*.odcs.yaml` and `models/input_ports/*.odcs.yaml`.
- If the user said "output contracts" / "input contracts" / "upstream drift", scope to one of those globs.
- If they did not, default to **all** ODCS files under both globs. List them, grouped by **Output ports** and **Input ports** so the user sees the two roles, then ask before running.
- Remember the resolved list as `CONTRACTS`. For each entry, also remember its role (`output` or `input`) — Step 4 surfaces failures differently.

### Step 2 — Select the server

For each contract in `CONTRACTS`:

- If the contract has exactly one server, use it.
- If it has multiple, default to `production`. If `production` is not defined, ask the user which one.
- Only pass `--server all` if the user explicitly asks to test every server.

### Step 3 — Run the test

For each contract — when it is an output-port contract, prefix the call with the inline `yq`-derived `DATACONTRACT_SNOWFLAKE_*` env vars from Step 0; when it is an input-port contract, run with whatever the user has exported:

```
datacontract test <path-to-contract>.odcs.yaml --server <server> --logs
```

Where `<path-to-contract>` is the file resolved in Step 1 — `datacontracts/<file>.odcs.yaml` for output contracts, or `models/input_ports/<file>.odcs.yaml` for input contracts. The CLI does not care which directory; the role only matters for how Step 4 reports the result and which credential strategy Step 3 uses.

- `--logs` ensures per-rule failure detail is in stdout — without it the CLI only prints a summary.
- If the user asks for a persisted report (e.g. to attach to a PR), add `--output ./test-results/<contract>.xml --output-format junit`.
- If the user asks to publish results back to Entropy Data (matches the generated CI workflow), add `--publish $API/test-results` where `$API` is the Entropy Data host. Do not publish by default — it writes server-side state.
- Capture stdout and exit code per contract. Non-zero exit means at least one rule failed.

Run sequentially, not in parallel — the warehouse is the bottleneck and parallel runs muddy the log output.

### Step 4 — Report

End with this two-part recap. Use the `Status` enum: `passed`, `failed`, `skipped` (missing creds).

**Part 1 — outcome table.** One row per contract tested. Group the rows: output-port contracts first, then input-port contracts under a sub-header (so the reader sees the two roles at a glance).

| Contract | Role | Server | Creds | Result | Failures | Details |
|---|---|---|---|---|---|---|
| `<contract-file>` | `output` / `input` | `<server>` | `profiles.yml` / `env` | `passed` / `failed` / `skipped` | count or `—` | one line per failing rule (field + rule), or "missing env var: …" if skipped |

**Part 2 — next steps.** Bullet list, include only what applies. Treat output vs. input failures differently:

- **Output-port failures**: surface the field and the violated check (e.g. `orders.order_id: not_null violated for 17 rows`). The fix is in this project — either the dbt model is wrong, the contract is wrong, or the data is wrong. If the user wants a follow-up SQL to find the offending rows, suggest the shape but do not run it.
- **Input-port failures**: this is upstream drift. Name the provider data product and output port (from the contract id and file name). The fix is *not* in this project — the user should contact the upstream owner, and in the meantime expect downstream output-port failures. Suggest re-running `dataproduct-implement` once upstream republishes a corrected contract, so the cached snapshot under `models/input_ports/` refreshes.
- For each `skipped` row, the exact env vars the user needs to set, and where to get them (usually the warehouse admin).
- If failures look like a data quality issue (rules unchanged, data drifted), suggest investigating the upstream of the failing model — this skill does not auto-fix data.

If everything passed, write a single line: `All <N> contracts pass against <server>.`

## Snowflake authentication

The Data Contract CLI reads credentials from environment variables, not from the contract file. Only the connection topology (account, database, schema, warehouse) belongs in the `servers` block.

ODCS server block:

```yaml
servers:
  - server: production
    type: snowflake
    account: abcdefg-xn12345
    database: ORDER_DB
    schema: ORDERS_PII_V2
```

Any env var prefixed `DATACONTRACT_SNOWFLAKE_` is forwarded to the Snowflake connector with the prefix stripped and the rest lowercased, so any Snowflake/Soda parameter can be passed this way. Three auth modes:

**Password auth**
```bash
export DATACONTRACT_SNOWFLAKE_USERNAME=...
export DATACONTRACT_SNOWFLAKE_PASSWORD=...
export DATACONTRACT_SNOWFLAKE_WAREHOUSE=COMPUTE_WH
export DATACONTRACT_SNOWFLAKE_ROLE=DATA_CONTRACT_TEST
```

**Private key (JWT) auth** — used for service accounts and CI:
```bash
export DATACONTRACT_SNOWFLAKE_USERNAME=SVC_DATACONTRACT
export DATACONTRACT_SNOWFLAKE_AUTHENTICATOR=SNOWFLAKE_JWT
export DATACONTRACT_SNOWFLAKE_PRIVATE_KEY_PATH=/secrets/snowflake_rsa.p8
# Only if the key is encrypted:
export DATACONTRACT_SNOWFLAKE_PRIVATE_KEY_PASSPHRASE=...
export DATACONTRACT_SNOWFLAKE_WAREHOUSE=COMPUTE_WH
export DATACONTRACT_SNOWFLAKE_ROLE=DATA_CONTRACT_TEST
```

**External browser SSO** — interactive, for local runs against an IdP-backed account:
```bash
export DATACONTRACT_SNOWFLAKE_USERNAME=jane.doe@example.com
export DATACONTRACT_SNOWFLAKE_AUTHENTICATOR=externalbrowser
export DATACONTRACT_SNOWFLAKE_WAREHOUSE=COMPUTE_WH
export DATACONTRACT_SNOWFLAKE_ROLE=DATA_CONTRACT_TEST
```

Not usable in CI — it opens a browser window.

## Constraints

- **Read-only against Snowflake.** This skill runs `datacontract test` which executes `SELECT` queries; it never writes. Do not invoke `datacontract publish`, `datacontract export`, or `entropy-data datacontracts put` from this skill.
- **No edits to contracts or models.** If a test fails, surface it — do not auto-patch the contract to make it pass. That defeats the purpose.
- **No credential sourcing.** If env vars are missing, tell the user; don't read them from `.env`, dotfiles, or anywhere else on the user's behalf.
- **Idempotent**: re-running the skill produces the same report against the same data. Failures from rules that depend on time (freshness, row-count windows) are expected to drift — note that in the failure detail when relevant.
