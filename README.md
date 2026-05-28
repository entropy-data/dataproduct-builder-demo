# dataproduct-builder-demo

Demo-grade coding-agent plugin for building **Snowflake** dbt data products with [Entropy Data](https://entropy-data.com).

This is the streamlined sibling of [dataproduct-builder-dbt](https://github.com/entropy-data/dataproduct-builder-dbt) — fewer skills, no platform branching, one batched question, and the implement skill runs dbt + tests + contract tests + OpenLineage on the spot so the data product shows up in Entropy Data in minutes.

## Skills

- **[dataproduct-bootstrap](skills/dataproduct-bootstrap/SKILL.md)** scaffolds a new Snowflake dbt data product from scratch: `dbt_project.yml`, model layout, README, `profiles.yml.example`, ODPS, output-port ODCS, OpenLineage transport, and a GitHub Actions workflow.
- **[dataproduct-implement](skills/dataproduct-implement/SKILL.md)** fetches a published data product, generates dbt models from its ODCS contract, runs `dbt-ol run` (which ships lineage to Entropy Data immediately), runs `dbt test`, and runs `datacontract test` — end-to-end in one pass.
- **[datacontract-test](skills/datacontract-test/SKILL.md)** runs `datacontract test` against output-port and input-port ODCS files to verify the live Snowflake data still matches the contract.

## Install

The skills are plain markdown; any coding agent that can read instruction files can run them.

### Claude Code

```
/plugin marketplace add https://github.com/entropy-data/dataproduct-builder-demo
/plugin install dataproduct-builder-demo@dataproduct-builder-demo
```

### OpenAI Codex

```
codex plugin marketplace add https://github.com/entropy-data/dataproduct-builder-demo
```

Then open Codex, run `/plugins`, and pick `dataproduct-builder-demo`.

### GitHub Copilot CLI

```
/plugin marketplace add https://github.com/entropy-data/dataproduct-builder-demo
/plugin install dataproduct-builder-demo@dataproduct-builder-demo
```

### Other agents (Cursor, Aider, etc.)

Any agent that reads `AGENTS.md` picks up the routing manifest. Or copy the `skills/` directory into the path your coding agent expects.

## Update

The plugin is updated in place; skills evolve as the demo gets sharper. Pull the latest version through your agent's marketplace.

### Claude Code

```
/plugin marketplace update dataproduct-builder-demo
```

### OpenAI Codex

```
codex plugin marketplace update dataproduct-builder-demo
```

### GitHub Copilot CLI

```
/plugin marketplace update dataproduct-builder-demo
```

### Other agents (Cursor, Aider, etc.)

`git pull` in the directory you cloned `skills/` from.

## Connect

Both skills authenticate against Entropy Data through a connection registered with the [entropy-data CLI](https://github.com/entropy-data/entropy-data-cli) (requires [uv](https://docs.astral.sh/uv/)).

The skills use a **per-project venv** for `entropy-data`, `datacontract`, `dbt`, and the rest. After `dataproduct-bootstrap` scaffolds a project, run `uv sync` from the project root to install everything at the pinned versions, then invoke them as `uv run <cli> …`.

The one exception is the first call to `dataproduct-bootstrap` itself, which runs against an empty directory (no `pyproject.toml`, no venv yet) and needs `entropy-data` available globally for its lookup step. Install once per machine:

```
uv tool install --upgrade entropy-data
entropy-data connection add default --api-key <your-api-key> --host <your-entropy-data-host>
```

Create a user-scoped key in the Entropy Data web UI (**Organization Settings → API Keys → Create new API key**, scope `User (personal token)`).

## Use

In an empty directory, ask the agent:

> Bootstrap a Snowflake dbt data product.

Then, once the scaffold is in place:

> Implement the data product *url or id*.

The implement skill runs end-to-end: it generates the models, runs `dbt-ol run` against your Snowflake target, runs `dbt test`, runs `datacontract test`, and ships the OpenLineage event so the pipeline shows up in Entropy Data right away. The GitHub Actions workflow is written to the repo as a reference for production use.

## Snowflake-only

This demo plugin drops multi-platform branching to keep the flow short. The user is asked one batched question, the templates are Snowflake-shaped, and the runtime invocations target the dbt Snowflake adapter and the `datacontract-cli[snowflake]` extras.

If you need Databricks / BigQuery / Postgres support, use the full builder at https://github.com/entropy-data/dataproduct-builder-dbt instead. Both plugins can coexist.

## License

MIT
