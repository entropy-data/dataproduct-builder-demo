{# Per dataproduct-builder-dbt's dataproduct-dbt skill: take `schema='...'` from
   model config literally (no profile-schema prefix) so each layer can land in
   its own Snowflake schema:

     - staging/ + intermediate/  →  internal_{{DBT_PROJECT_NAME}}
     - output_ports/v<N>/<table> →  op_<output_port_id>_v<N>

   Without this override, dbt's default `generate_schema_name` concatenates the
   target's default schema with `+schema:` overrides, which leaks the data
   product's internal layer name into the output-port schema. #}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
