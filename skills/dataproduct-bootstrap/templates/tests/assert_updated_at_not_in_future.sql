-- Custom data test — fails if any row in the output port has a future timestamp.
-- This is a placeholder; replace with project-specific business-rule assertions
-- once `dataproduct-implement` materializes the model.
-- See https://www.entropy-data.com/learn/data-products-with-dbt#testing

select ID
from {{ ref('{{TABLE}}') }}
where UPDATED_AT > current_timestamp()
