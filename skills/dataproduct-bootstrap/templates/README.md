# {{DATA_PRODUCT_NAME}}

dbt data product `{{DATA_PRODUCT_ID}}` on Snowflake. Published to [Entropy Data](https://entropy-data.com).

## Install

Project Python deps (dbt-core, dbt-snowflake, openlineage-dbt, datacontract-cli[snowflake], entropy-data):

```bash
uv sync
```

`uv sync` creates `.venv/` with everything from `pyproject.toml`'s `[dependency-groups].dev`. All invocations below use the venv via `uv run` — no activation needed.

## Configure

Copy `profiles.yml.example` to `~/.dbt/profiles.yml` (or merge it in) and fill in your Snowflake credentials.

Set the Entropy Data API key for OpenLineage transport:

```bash
export OPENLINEAGE__TRANSPORT__AUTH__APIKEY=<your-entropy-data-api-key>
```

Set the Data Contract CLI credentials for Snowflake (the CLI reads `DATACONTRACT_SNOWFLAKE_*` env vars, not `~/.dbt/profiles.yml`):

```bash
export DATACONTRACT_SNOWFLAKE_USERNAME=<your-snowflake-user>
export DATACONTRACT_SNOWFLAKE_PASSWORD=<your-snowflake-password>
export DATACONTRACT_SNOWFLAKE_ROLE=<your-snowflake-role>
export DATACONTRACT_SNOWFLAKE_WAREHOUSE=<your-snowflake-warehouse>
```

## Run

```bash
uv run dbt-ol run    # runs dbt and ships OpenLineage to Entropy Data
uv run dbt test
uv run datacontract test models/output_ports/v1/{{CONTRACT_FILE}} --server production --logs
```

## Layout

```
models/
├── input_ports/      # external sources you read from
├── staging/          # 1:1 cleaned views over input ports
├── intermediate/     # joined / shaped views
└── output_ports/v1/  # published tables — one per output port, ODCS contract alongside
```

## Publishing

CI in `.github/workflows/data-product.yml` runs `dbt-ol run`, `dbt test`, publishes the ODPS + ODCS to Entropy Data, and runs the data contract test.
