{{ config(materialized='ephemeral') }}

{%- set selected_fields = [
    "id",
    "name",
    "budget",
    "status",
    "modified_time",
    "account_id",
    "type"
] -%}
{%- set schema_name, table_name = 'bingads_raw', 'campaigns' -%}

WITH staging AS 
    (SELECT 
        {% for field in selected_fields|reject("eq","modified_time") -%}
        {{ get_bingads_clean_field(table_name, field) }}
        {%- if not loop.last %},{%- endif %}
        {% endfor -%}
    FROM 
        (SELECT
            {{ selected_fields|join(", ") }},
            MAX(modified_time) OVER (PARTITION BY id) as last_modified_at
        FROM {{ source(schema_name, table_name) }})
    WHERE modified_time = last_modified_at
    )

SELECT *,
    campaign_id as unique_key
FROM staging 