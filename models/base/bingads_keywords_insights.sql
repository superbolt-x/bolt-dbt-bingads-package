{%- set currency_fields = [
    "spend",
    "revenue",
    "all_revenue"
]
-%}

{%- set exclude_fields = [
    "unique_key",
    "_fivetran_synced",
    "ad_distribution",
    "account_id",
    "campaign_id",
    "ad_group_id",
    "bid_match_type",
    "delivered_match_type",
    "keyword_status",
    "currency_code",
    "device_os",
    "device_type",
    "language",
    "network",
    "top_vs_other",
    "average_position",
    "conversions_qualified",
    "all_conversions_qualified",
    "current_max_cpc",
    "quality_score",
    "expected_ctr",
    "ad_relevance",
    "landing_page_experience",
    "historical_quality_score",
    "historical_expected_ctr",
    "historical_ad_relevance",
    "historical_landing_page_experience",
    "quality_impact",
    "keyword__status",
    "all_return_on_ad_spend"
]
-%}

{%- set stg_fields = get_bingads_column_names(ref('_stg_bingads_keywords_insights'))
                    |reject("in",exclude_fields)
                    -%}

WITH 
    {% if var('currency') != 'USD' -%}
    currency AS
    (SELECT DISTINCT date, "{{ var('currency') }}" as raw_rate, 
        LAG(raw_rate) ignore nulls over (order by date) as exchange_rate
    FROM utilities.dates 
    LEFT JOIN utilities.currency USING(date)
    WHERE date <= current_date),
    {%- endif -%}

    {%- set exchange_rate = 1 if var('currency') == 'USD' else 'exchange_rate' %}

    insights AS 
    (SELECT 
        {%- for field in stg_fields -%}
        {%- if field in currency_fields or '_value' in field %}
        "{{ field }}"::float/{{ exchange_rate }} as "{{ field }}"
        {%- else %}
        "{{ field }}"
        {%- endif -%}
        {%- if not loop.last %},{%- endif %}
        {%- endfor %}
    FROM {{ ref('_stg_bingads_keywords_insights') }}
    {%- if var('currency') != 'USD' %}
    LEFT JOIN currency USING(date)
    {%- endif %}
    )

    
SELECT *,
    {{ bolt_dbt_utils.get_date_parts('date') }}
FROM insights 
