{{ config (
    alias = target.database + '_bingads_performance_by_keyword',
    materialized = 'incremental',
    unique_key = 'unique_key',
    incremental_strategy = 'delete+insert',
    on_schema_change = 'append_new_columns'
)}}

{#-
    Keyword performance, all date granularities in one table.

    Reads the day-grain incremental staging model directly (the redundant
    bingads_keywords_insights middle table is disabled): currency conversion
    and date parts are applied inline here, then day/week/month/quarter/year
    are rolled up.

    Incremental: daily runs reprocess from the start of the year containing
    (max date - bingads_lookback_days). Reading whole periods keeps the coarser
    roll-ups complete; data older than the conversion lookback does not change.
    Run --full-refresh periodically to rebuild history and refresh keyword/
    campaign metadata on older rows.
-#}

{%- set currency_fields = [
    "spend",
    "revenue",
    "all_revenue"
]
-%}

{#- Columns dropped when projecting staging -> insights
    (was the bingads_keywords_insights middle model's exclude list). -#}
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

{%- set stg_fields = adapter.get_columns_in_relation(ref('_stg_bingads_keywords_insights'))
                    |map(attribute="name")
                    |reject("in",exclude_fields)
                    |list
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
    {% if is_incremental() -%}
    where date >= date_trunc('year', (select dateadd(day,-{{ var('bingads_lookback_days', 31) }},max(date)) from {{ this }}))::date
    {%- endif %}
    ),

    insights_stg AS
    (SELECT *,
    {{ bolt_dbt_utils.get_date_parts('date') }}
    FROM insights),

{%- set date_granularity_list = ['day','week','month','quarter','year'] -%}
{%- set measure_exclude = ['date','day','week','month','quarter','year','last_updated','unique_key','destination_url'] -%}
{%- set dimensions = ['keyword_id'] -%}
{%- set measures = stg_fields
                    |reject("in",measure_exclude)
                    |reject("in",dimensions)
                    |list
                    -%}

    {%- for date_granularity in date_granularity_list %}

    performance_{{date_granularity}} AS
    (SELECT
        '{{date_granularity}}' as date_granularity,
        {{date_granularity}} as date,
        {%- for dimension in dimensions %}
        {{ dimension }},
        {%-  endfor %}
        {% for measure in measures -%}
        COALESCE(SUM("{{ measure }}"),0) as "{{ measure }}"
        {%- if not loop.last %},{%- endif %}
        {% endfor %}
    FROM insights_stg
    GROUP BY {{ range(1, dimensions|length +2 +1)|list|join(',') }}
    ),
    {%- endfor %}

    keywords AS
    (SELECT keyword_id, ad_group_id, name, match_type, status
    FROM {{ ref('bingads_keywords') }}
    ),

    ad_groups AS
    (SELECT ad_group_id, ad_group_name, ad_group_status, campaign_id
    FROM {{ ref('bingads_ad_groups') }}
    ),

    campaigns AS
    (SELECT campaign_id, campaign_name, campaign_budget, campaign_status, account_id, campaign_type
    FROM {{ ref('bingads_campaigns') }}
    ),

    accounts AS
    (SELECT account_id, account_name, account_currency_code
    FROM {{ ref('bingads_accounts') }}
    )

SELECT *,
    {{ get_bingads_default_campaign_types('campaign_name')}},
    date||'_'||date_granularity||'_'||ad_group_id||'_'||keyword_id as unique_key
FROM
    ({% for date_granularity in date_granularity_list -%}
    SELECT *
    FROM performance_{{date_granularity}}
    {% if not loop.last %}UNION ALL
    {% endif %}

    {%- endfor %}
    )
LEFT JOIN keywords USING(keyword_id)
LEFT JOIN ad_groups USING(ad_group_id)
LEFT JOIN campaigns USING(campaign_id)
LEFT JOIN accounts USING(account_id)
