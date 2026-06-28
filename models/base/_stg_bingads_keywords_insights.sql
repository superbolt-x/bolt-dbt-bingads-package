{{ config(
        materialized='incremental',
        unique_key='unique_key'
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

{%- set insights_fields = adapter.get_columns_in_relation(source(schema_name, insights_table_name))
                    |map(attribute="name")
                    |reject("in",insights_exclude_fields)
                    -%}

{#- Custom conversions live in the conversion report, one row per keyword x goal,
    at a coarser grain than the (segmented) performance report. Pull the distinct
    goal values, pivot each into its own column, and fold them into the keyword-
    grain aggregate so insights_agg carries the custom conversions alongside the
    standard measures.

    Grain note: the performance report and the conversion report are each
    aggregated to keyword grain *before* they are joined, so conversions are not
    fanned out / double counted across the performance report's segment rows
    (device, network, match type, ...). -#}
{%- set convtype_relation = source(schema_name, convtype_table_name) -%}
{%- set convtype_table_exists = bolt_dbt_utils.check_source_exists(schema_name, convtype_table_name) -%}
{%- if convtype_table_exists -%}
    {%- set goals = dbt_utils.get_column_values(convtype_relation, 'goal', where="goal IS NOT NULL AND goal != ''") -%}
{%- else -%}
    {%- set goals = [] -%}
{%- endif -%}
{%- set bingads_conv = var('bingads_conversion_used_by_custom_conversions') -%}
{%- set conv_value_map = {'conversions': 'revenue', 'all_conversions': 'all_revenue'} -%}

WITH insights AS
    (SELECT
        {%- for field in insights_fields %}
        {{ get_bingads_clean_field(insights_table_name, field) }}
        {%- if not loop.last %},{%- endif %}
        {%- endfor %}
    FROM {{ source(schema_name, insights_table_name) }}
    )

, perf_agg AS (
    SELECT
        date,
        account_id,
        campaign_id,
        ad_group_id,
        keyword_id,
        SUM(impressions)      as impressions,
        SUM(clicks)           as clicks,
        SUM(spend)            as spend,
        SUM(conversions)      as conversions,
        SUM(all_conversions)  as all_conversions,
        SUM(revenue)          as revenue,
        SUM(all_revenue)      as all_revenue,
        SUM(assists)          as assists,
        MAX(currency_code)    as currency_code,
        MAX(_fivetran_synced) as _fivetran_synced
    FROM insights
    GROUP BY 1,2,3,4,5
)

{%- if convtype_table_exists and goals %}
, convtype AS (
    SELECT
        date,
        ad_group_id,
        keyword_id,
        {% for goal in goals -%}
        COALESCE(SUM(CASE WHEN goal = '{{ goal }}' THEN {{ bingads_conv }} ELSE 0 END), 0)                as "{{ get_bingads_clean_conversion_name(goal) }}",
        COALESCE(SUM(CASE WHEN goal = '{{ goal }}' THEN {{ conv_value_map[bingads_conv] }} ELSE 0 END), 0) as "{{ get_bingads_clean_conversion_name(goal) }}_value"
        {%- if not loop.last %},{%- endif %}
        {% endfor %}
    FROM {{ convtype_relation }}
    GROUP BY 1,2,3
)
{%- endif %}

, insights_agg AS (
    SELECT
        perf_agg.*
        {%- if convtype_table_exists and goals %}
        {%- for goal in goals %}
        , convtype."{{ get_bingads_clean_conversion_name(goal) }}"
        , convtype."{{ get_bingads_clean_conversion_name(goal) }}_value"
        {%- endfor %}
        {%- endif %}
    FROM perf_agg
    {%- if convtype_table_exists and goals %}
    LEFT JOIN convtype
        ON  perf_agg.date         = convtype.date
        AND perf_agg.ad_group_id  = convtype.ad_group_id
        AND perf_agg.keyword_id   = convtype.keyword_id
    {%- endif %}
)

SELECT *,
    MAX(_fivetran_synced) over (PARTITION BY account_id) as last_updated,
    ad_group_id||'_'||keyword_id||'_'||date as unique_key
FROM insights_agg
{% if is_incremental() -%}

where date >= (select max(date) - {{ var('bingads_lookback_days', 31) }} from {{ this }})

{% endif %}
