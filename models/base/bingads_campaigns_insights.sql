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
    "campaign_name",
    "campaign_status",
    "currency_code",
    "delivered_match_type",
    "device_type",
    "network",
    "average_position",
    "conversions_qualified",
    "low_quality_clicks",
    "low_quality_impressions",
    "low_quality_conversions",
    "low_quality_general_clicks",
    "low_quality_sophisticated_clicks",
    "quality_socre",
    "ad_relevance",
    "landing_page_experience",
    "phone_impressions",
    "phone_calls",
    "all_conversions_qualified"
]
-%}

{%- set stg_fields = get_bingads_column_names(ref('_stg_bingads_campaigns_insights'))
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
    FROM {{ ref('_stg_bingads_campaigns_insights') }}
    {%- if var('currency') != 'USD' %}
    LEFT JOIN currency USING(date)
    {%- endif %}
    )

    
SELECT *,
    {{ bolt_dbt_utils.get_date_parts('date') }}
FROM insights 


