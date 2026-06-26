{{ config(
        materialized='incremental',
        unique_key='unique_key',
        on_schema_change='sync_all_columns'
) }}


{%- set schema_name, insights_table_name, convtype_table_name = 'bingads_raw', 'keyword_performance_daily_report', 'conversion_performance_daily_report' -%}
{%- set insights_exclude_fields = [
   "ctr",
   "average_cpc",
   "conversion_rate",
   "cost_per_conversion",
   "return_on_ad_spend",
   "cost_per_assist",
   "revenue_per_conversion",
   "revenue_per_assist",
   "all_conversion_rate",
   "all_cost_per_conversion",
   "all_revenue_on_ad_spend",
   "all_revenue_per_conversion"
]
-%}
{%- set convtype_include_fields = [
    "date",
    "ad_group_id",
    "keyword_id",
    "goal",
    "conversions",
    "all_conversions",
    "revenue",
    "all_revenue"
]-%}

{%- set insights_fields = adapter.get_columns_in_relation(source(schema_name, insights_table_name))
                    |map(attribute="name")
                    |reject("in",insights_exclude_fields)
                    -%}

WITH insights AS
    (SELECT
        {%- for field in insights_fields %}
        {{ get_bingads_clean_field(insights_table_name, field) }}
        {%- if not loop.last %},{%- endif %}
        {%- endfor %}
    FROM {{ source(schema_name, insights_table_name) }}
    )

, insights_agg AS (
    SELECT
        date,
        account_id,
        campaign_id,
        ad_group_id,
        keyword_id,
        SUM(impressions)     as impressions,
        SUM(clicks)          as clicks,
        SUM(spend)           as spend,
        SUM(conversions)     as conversions,
        SUM(all_conversions) as all_conversions,
        SUM(revenue)         as revenue,
        SUM(all_revenue)     as all_revenue,
        SUM(assists)         as assists,
        MAX(currency_code)   as currency_code,
        MAX(_fivetran_synced) as _fivetran_synced
    FROM insights
    GROUP BY 1,2,3,4,5
)

    {% set convtype_table_exists = bolt_dbt_utils.check_source_exists(schema_name, convtype_table_name) -%}
    {%- if not convtype_table_exists %}

    {%- else -%}
    , convtype_raw AS (
    SELECT {{ convtype_include_fields|join(", ") }}
    FROM {{ source(schema_name, convtype_table_name) }}
    )

    {% set conversions = dbt_utils.get_column_values(source(schema_name, convtype_table_name), 'goal', where="goal IS NOT NULL AND goal != ''") -%}
    {% set bingads_conv = var('bingads_conversion_used_by_custom_conversions') -%}
    {% set conv_value_map = {'conversions': 'revenue', 'all_conversions': 'all_revenue'} -%}
    , convtype AS (
    SELECT
        date,
        ad_group_id,
        keyword_id,
        {% for conversion in conversions -%}
        COALESCE(SUM(CASE WHEN goal = '{{conversion}}' THEN {{ bingads_conv }} ELSE 0 END), 0) as "{{get_bingads_clean_conversion_name(conversion)}}",
        COALESCE(SUM(CASE WHEN goal = '{{conversion}}' THEN {{ conv_value_map[bingads_conv] }} ELSE 0 END), 0) as "{{get_bingads_clean_conversion_name(conversion)}}_value"
        {%- if not loop.last %},{%- endif %}
        {% endfor %}
    FROM convtype_raw
    GROUP BY 1, 2, 3
    )
    {%- endif %}

SELECT *,
    MAX(_fivetran_synced) over (PARTITION BY account_id) as last_updated,
    ad_group_id||'_'||keyword_id||'_'||date as unique_key
FROM insights_agg
{%- if convtype_table_exists %}
LEFT JOIN convtype USING(date, ad_group_id, keyword_id)
{%- endif %}
{% if is_incremental() -%}

where date >= (select max(date)-30 from {{ this }})

{% endif %}
