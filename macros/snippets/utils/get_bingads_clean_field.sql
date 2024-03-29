{%- macro get_bingads_clean_field(table_name, column_name) -%}

    {# /* Apply to all tables */ #}

    {%- if column_name in ('last_modified_time','modified_time') -%}
    {{column_name}} as updated_at
    
    {%- elif column_name == 'impression_share_percent' -%}
    {{column_name}}::float/100::float as impression_share

    {%- elif column_name == 'impression_lost_to_budget_percent' -%}
    {{column_name}}::float/100::float as impression_lost_to_budget_percent

    {%- elif column_name == 'impression_lost_to_rank_agg_percent' -%}
    {{column_name}}::float/100::float as impression_lost_to_rank_agg_percent

    {%- elif 'keyword' in column_name and column_name != 'keyword_id' -%}
    {{column_name}} as keyword_{{column_name.split('keyword')[1]}}

    {#- /* Apply to specific table */ -#}
    {%- elif "account" in table_name -%}

        {{column_name}} as account_{{column_name}}
    
    {%- elif "campaigns" in table_name -%}

        {%- if "_id" not in column_name  -%}
        {{column_name}} as campaign_{{column_name}}

        {%- else -%}
        {{column_name}}
        
        {%- endif -%}

    {%- elif "ad_groups" in table_name -%}

        {%- if "_id" not in column_name  -%}
        {{column_name}} as ad_group_{{column_name}}

        {%- else -%}
        {{column_name}}
        
        {%- endif -%}

    {%- elif "ads" in table_name -%}

        {%- if "_id" not in column_name  -%}
        {{column_name}} as ad_{{column_name}}

        {%- else -%}
        {{column_name}}
        
        {%- endif -%}

    {%- elif "keyword" in table_name -%}

        {%- if column_name == 'id' -%}
        {{column_name}} as keyword_{{column_name}}

        {%- else -%}
        {{column_name}}
        
        {%- endif -%}

    {%- else -%}
    {{column_name}} 

    {%- endif -%}

{% endmacro -%}
