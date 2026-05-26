{%- macro get_bingads_clean_conversion_name(conversion_name) -%}

    {%- call statement('results', fetch_result=True) -%}

    SELECT TRANSLATE(lower('{{conversion_name}}'),'().&- !:/+|<>','')

    {%- endcall -%}

    {% if execute %}
    {{ return(load_result('results')['data'][0][0]) }}
    {% endif %}

{%- endmacro -%}
