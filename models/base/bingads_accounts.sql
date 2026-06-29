{{ config(materialized='ephemeral') }}

{%- set selected_fields = [
    "id",
    "name",
    "currency_code",
    "last_modified_time"
] -%}
{%- set schema_name, table_name = 'bingads_raw', 'accounts' -%}

WITH staging AS 
    (SELECT 
        {% for field in selected_fields|reject("eq","last_modified_time") -%}
        {{ get_bingads_clean_field(table_name, field) }}
        {%- if not loop.last %},{%- endif %}
        {% endfor -%}
    FROM 
        (SELECT
            {{ selected_fields|join(", ") }},
            MAX(last_modified_time) OVER (PARTITION BY id) as last_modified_at
        FROM {{ source(schema_name, table_name) }})
    WHERE last_modified_time = last_modified_at
    )

SELECT *,
    account_id as unique_key
FROM staging 