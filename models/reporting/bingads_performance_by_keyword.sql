{{ config (
    alias = target.database + '_bingads_performance_by_keyword'
)}}

{%- set date_granularity_list = ['day','week','month','quarter','year'] -%}
{%- set exclude_fields = ['date','day','week','month','quarter','year','last_updated','unique_key','destination_url'] -%}
{%- set dimensions = ['keyword_id'] -%}
{%- set measures = adapter.get_columns_in_relation(ref('bingads_keywords_insights'))
                    |map(attribute="name")
                    |reject("in",exclude_fields)
                    |reject("in",dimensions)
                    |list
                    -%}  

WITH 
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
    FROM {{ ref('bingads_keywords_insights') }}
    GROUP BY {{ range(1, dimensions|length +2 +1)|list|join(',') }}
    ),
    {%- endfor %}

    keywords AS
    (SELECT keyword_id, ad_group_id, name, match_type, status
    FROM {{ ref('bingads_keywords') }}
    ),

    ad_groups AS 
    (SELECT {{ dbt_utils.star(from = ref('bingads_ad_groups'), except = ["unique_key"]) }}
    FROM {{ ref('bingads_ad_groups') }}
    ),

    campaigns AS 
    (SELECT {{ dbt_utils.star(from = ref('bingads_campaigns'), except = ["unique_key"]) }}
    FROM {{ ref('bingads_campaigns') }}
    ),

    accounts AS 
    (SELECT {{ dbt_utils.star(from = ref('bingads_accounts'), except = ["unique_key"]) }}
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
