{{ config( 
        materialized='incremental',
        unique_key='unique_key'
) }}


{%- set schema_name, insights_table_name, convtype_table_name = 'bingads_raw', 'campaign_impression_performance_daily_report', 'conversion_performance_daily_report' -%}
{%- set insights_exclude_fields = [
   "_fivetran_id",
   "ctr",
   "expected_ctr",
   "historical_expected_ctr",
   "historical_ad_relevance",
   "historical_landing_page_experience",
   "ptr",
   "average_cpc",
   "conversion_rate",
   "cost_per_conversion",
   "low_quality_clicks_percent",
   "low_quality_impressions_percent",
   "low_quality_conversion_rate",
   "return_on_ad_spend",
   "cost_per_assist",
   "revenue_per_conversion",
   "revenue_per_assist",
   "all_conversion_rate",
   "all_cost_per_conversion",
   "all_revenue_on_ad_spend",
   "all_revenue_per_conversion",
   "custom_parameters",
   "absolute_top_impression_share_lost_to_rank_percent",
   "absolute_top_impression_share_percent",
   "absolute_top_impression_share_lost_to_budget_percent",
   "absolute_top_impression_rate_percent",
   "exact_match_impression_share_percent",
   "top_impression_share_lost_to_rank_percent",
   "top_impression_share_percent",
   "top_impression_share_lost_to_budget_percent",
   "top_impression_rate_percent",
   "impression_lost_to_rank_agg_percent",
   "impression_lost_to_budget_percent"
]
-%}

{%- set convtype_include_fields = [
    "date",
    "campaign_id",
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

    {% set convtype_table_exists = bolt_dbt_utils.check_source_exists(schema_name, convtype_table_name) -%}
    {%- if not convtype_table_exists %}

    {%- else -%}
    , convtype_raw AS (
    SELECT {{ convtype_include_fields|join(", ") }}
    FROM {{ source(schema_name, convtype_table_name) }}
    )

    {% set conversions = dbt_utils.get_column_values(source(schema_name, convtype_table_name), 'goal', where="goal != '' AND goal IS NOT NULL") -%}
    {% set bingads_conv = var('bingads_conversion_used_by_custom_conversions') -%}
    {% set conv_value_map = {'conversions': 'revenue', 'all_conversions': 'all_revenue'} -%}
    , convtype AS (
    SELECT
        date,
        campaign_id,
        {% for conversion in conversions -%}
        COALESCE(SUM(CASE WHEN goal = '{{conversion}}' THEN {{ bingads_conv }} ELSE 0 END), 0) as "{{get_bingads_clean_conversion_name(conversion)}}",
        COALESCE(SUM(CASE WHEN goal = '{{conversion}}' THEN {{ conv_value_map[bingads_conv] }} ELSE 0 END), 0) as "{{get_bingads_clean_conversion_name(conversion)}}_value"
        {%- if not loop.last %},{%- endif %}
        {% endfor %}
    FROM convtype_raw
    GROUP BY 1, 2
    )
    {%- endif %}

SELECT *,
    MAX(_fivetran_synced) over (PARTITION BY account_id) as last_updated,
    campaign_id||'_'||date as unique_key
FROM insights
{%- if convtype_table_exists %}
LEFT JOIN convtype USING(date, campaign_id)
{%- endif %}
{% if is_incremental() -%}

where date >= (select max(date) - {{ var('bingads_lookback_days', 31) }} from {{ this }})

{% endif %}
