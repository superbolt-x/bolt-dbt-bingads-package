{%- macro get_bingads_column_names(relation) -%}

    {#- /* Reliable column introspection for Redshift.

       dbt's adapter.get_columns_in_relation() reads information_schema.columns,
       which on this cluster returns a stale / truncated column set for the
       Fivetran-managed bingads tables (only a subset of the real columns is
       returned, so recently added columns such as view_through_conversions are
       silently dropped from every dynamic model). svv_columns reflects the true
       current schema, so we introspect it directly instead.

       Returns a list of column names ordered by their position in the table,
       mirroring the output of adapter.get_columns_in_relation(...)|map(attribute="name"). */ -#}

    {%- if not execute -%}
        {{ return([]) }}
    {%- endif -%}

    {%- set column_query -%}
        select column_name
        from svv_columns
        where table_schema = lower('{{ relation.schema }}')
          and table_name = lower('{{ relation.identifier }}')
        order by ordinal_position
    {%- endset -%}

    {%- set results = run_query(column_query) -%}
    {{ return(results.columns[0].values()) }}

{%- endmacro -%}
