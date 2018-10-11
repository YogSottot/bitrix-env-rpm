#!/bin/bash
printf "%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s\n" \
    "type" \
    "openvz" \
    "query_cache_size" \
    "query_cache_limit" \
    "max_connections" \
    "table_open_cache" \
    "thread_cache_size" \
    "max_heap_table_size" \
    "tmp_table_size" \
    "key_buffer" \
    "join_buffer_size" \
    "sort_buffer_size" \
    "bulk_insert_buffer_size" \
    "myisam_sort_buffer_size" \
    "mysql_innodb_buffer_pool_size"

for file in $( ls -al *bvat.cnf.j2 | awk '{print $9}' | sort -n ); do
    type=$(echo $file| awk -F'_' '{print $1}')
    IFS_BAK=$IFS
    IFS=$'\n'
    is_openvz_values=1
    query_cache_size=
    query_cache_limit=
    max_connections=
    table_open_cache=
    thread_cache_size=
    max_heap_table_size=
    tmp_table_size=
    key_buffer=
    join_buffer_size=
    sort_buffer_size=
    bulk_insert_buffer_size=
    myisam_sort_buffer_size=
    innodb_buffer_pool_size=


    for line in $(cat $file); do
        [[ $(echo "$line" | grep -wc query_cache_size)          -gt 0 ]] && \
            query_cache_size=$(         echo "$line" | awk -F'=' '{print $2}' | sed -e 's/\s\+//g')
        [[ $(echo "$line" | grep -wc query_cache_limit)         -gt 0 ]] && \
            query_cache_limit=$(        echo "$line" | awk -F'=' '{print $2}' | sed -e 's/\s\+//g')
        [[ $(echo "$line" | grep -wc max_connections)           -gt 0 ]] && \
            max_connections=$(          echo "$line" | awk -F'=' '{print $2}' | sed -e 's/\s\+//g')
        [[ $(echo "$line" | grep -wc table_open_cache)          -gt 0 ]] && \
            table_open_cache=$(         echo "$line" | awk -F'=' '{print $2}' | sed -e 's/\s\+//g')
        [[ $(echo "$line" | grep -wc thread_cache_size)         -gt 0 ]] && \
            thread_cache_size=$(        echo "$line" | awk -F'=' '{print $2}' | sed -e 's/\s\+//g')
        [[ $(echo "$line" | grep -wc max_heap_table_size)       -gt 0 ]] && \
            max_heap_table_size=$(      echo "$line" | awk -F'=' '{print $2}' | sed -e 's/\s\+//g')
        [[ $(echo "$line" | grep -wc tmp_table_size)            -gt 0 ]] && \
            tmp_table_size=$(           echo "$line" | awk -F'=' '{print $2}' | sed -e 's/\s\+//g')
        [[ $(echo "$line" | grep -c key_buffer)                 -gt 0 ]] && \
            key_buffer=$(               echo "$line" | awk -F'=' '{print $2}' | sed -e 's/\s\+//g')
        [[ $(echo "$line" | grep -wc join_buffer_size)          -gt 0 ]] && \
            join_buffer_size=$(         echo "$line" | awk -F'=' '{print $2}' | sed -e 's/\s\+//g')
        [[ $(echo "$line" | grep -wc sort_buffer_size)          -gt 0 ]] && \
            sort_buffer_size=$(         echo "$line" | awk -F'=' '{print $2}' | sed -e 's/\s\+//g')
        [[ $(echo "$line" | grep -wc bulk_insert_buffer_size)   -gt 0 ]] && \
            bulk_insert_buffer_size=$(  echo "$line" | awk -F'=' '{print $2}' | sed -e 's/\s\+//g')
        [[ $(echo "$line" | grep -wc myisam_sort_buffer_size)   -gt 0 ]] && \
            myisam_sort_buffer_size=$(  echo "$line" | awk -F'=' '{print $2}' | sed -e 's/\s\+//g')
        [[ $(echo "$line" | grep -wc innodb_buffer_pool_size)   -gt 0 ]] && \
            innodb_buffer_pool_size=$(  echo "$line" | egrep -o "default\(\S+\)" | awk -F"'" '{print $2}')




        if [[ ( $(echo "$line" | grep -wc "else") -gt 0 ) && ( -n $myisam_sort_buffer_size ) ]]; then
            is_openvz_values=0
            printf "%d:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s\n" \
                "$type" \
                "openvz" \
                "$query_cache_size" \
                "$query_cache_limit" \
                "$max_connections" \
                "$table_open_cache" \
                "$thread_cache_size" \
                "$max_heap_table_size" \
                "$tmp_table_size" \
                "$key_buffer" \
                "$join_buffer_size" \
                "$sort_buffer_size" \
                "$bulk_insert_buffer_size" \
                "$myisam_sort_buffer_size" \
                "$innodb_buffer_pool_size"

            query_cache_size=
            query_cache_limit=
            max_connections=
            table_open_cache=
            thread_cache_size=
            max_heap_table_size=
            tmp_table_size=
            key_buffer=
            join_buffer_size=
            sort_buffer_size=
            bulk_insert_buffer_size=
            myisam_sort_buffer_size=

        fi
    done
    printf "%d:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s\n" \
        "$type" \
        "general" \
        "$query_cache_size" \
        "$query_cache_limit" \
        "$max_connections" \
        "$table_open_cache" \
        "$thread_cache_size" \
        "$max_heap_table_size" \
        "$tmp_table_size" \
        "$key_buffer" \
        "$join_buffer_size" \
        "$sort_buffer_size" \
        "$bulk_insert_buffer_size" \
        "$myisam_sort_buffer_size" \
        "$innodb_buffer_pool_size"
 
    IFS=$IFS_BAK
    IFS_BAK=

done
