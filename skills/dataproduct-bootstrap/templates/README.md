# {{DATA_PRODUCT_NAME}}

dbt data product `{{DATA_PRODUCT_ID}}` on Snowflake. Published to [Entropy Data](https://entropy-data.com).

## Install

```bash
uv venv
source .venv/bin/activate
uv pip install dbt-core dbt-snowflake openlineage-dbt datacontract-cli entropy-data
```

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
source .venv/bin/activate
dbt-ol run    # runs dbt and ships OpenLineage to Entropy Data
dbt test
datacontract test datacontracts/{{CONTRACT_FILE}} --server production --logs
```

## Layout

Follows [Building Data Products with dbt](https://www.entropy-data.com/learn/data-products-with-dbt):

```
datacontracts/        # ODCS data contracts — source of truth for the output schema
models/
├── input_ports/      # external sources you read from (sources.yml + per-agreement files)
├── staging/          # 1:1 cleaned views over input ports — stg_*.sql
├── intermediate/     # joined / shaped views — int_*.sql
└── output_ports/     # published tables — one .sql + .yml per output port
tests/                # custom data tests — assert_*.sql
```

## Publishing

CI in `.github/workflows/data-product.yml` runs `dbt-ol run`, `dbt test`, publishes the ODPS + ODCS to Entropy Data, and runs the data contract test.
