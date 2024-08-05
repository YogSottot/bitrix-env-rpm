#!/usr/bin/bash
#
file=perf.csv
#
# general
IFS_BAK=$IFS
IFS=$IFS_BAK

echo "bvat_settings:"
echo "  general:"
for line in $(grep -v "myisam_sort_buffer_size" "$file" | grep -w general | sort -n); do
    type=$(echo $line | awk -F':' '{print $1}')
    echo "    type${type}:"
    echo "      query_cache_size: $(echo $line | awk -F':' '{print $3}')"
    echo "      query_cache_limit: $(echo $line | awk -F':' '{print $4}')"
    echo "      max_connections: $(echo $line | awk -F':' '{print $5}')"
    echo "      table_open_cache: $(echo $line | awk -F':' '{print $6}')"
    echo "      thread_cache_size: $(echo $line | awk -F':' '{print $7}')"
    echo "      max_heap_table_size: $(echo $line | awk -F':' '{print $8}')"
    echo "      tmp_table_size: $(echo $line | awk -F':' '{print $9}')"
    echo "      key_buffer: $(echo $line | awk -F':' '{print $10}')"
    echo "      join_buffer_size: $(echo $line | awk -F':' '{print $11}')"
    echo "      sort_buffer_size: $(echo $line | awk -F':' '{print $12}')"
    echo "      bulk_insert_buffer_size: $(echo $line | awk -F':' '{print $13}')"
    echo "      myisam_sort_buffer_size: $(echo $line | awk -F':' '{print $14}')"
    echo "      mysql_innodb_buffer_pool_size: $(echo $line | awk -F':' '{print $15}' | sed 's/M//')"

done

echo "openvz:"
for line in $(grep -v "myisam_sort_buffer_size" "$file" | grep -w openvz | sort -n); do
    type=$(echo $line | awk -F':' '{print $1}')
    echo "    type${type}:"
    echo "      query_cache_size: $(echo $line | awk -F':' '{print $3}')"
    echo "      query_cache_limit: $(echo $line | awk -F':' '{print $4}')"
    echo "      max_connections: $(echo $line | awk -F':' '{print $5}')"
    echo "      table_open_cache: $(echo $line | awk -F':' '{print $6}')"
    echo "      thread_cache_size: $(echo $line | awk -F':' '{print $7}')"
    echo "      max_heap_table_size: $(echo $line | awk -F':' '{print $8}')"
    echo "      tmp_table_size: $(echo $line | awk -F':' '{print $9}')"
    echo "      key_buffer: $(echo $line | awk -F':' '{print $10}')"
    echo "      join_buffer_size: $(echo $line | awk -F':' '{print $11}')"
    echo "      sort_buffer_size: $(echo $line | awk -F':' '{print $12}')"
    echo "      bulk_insert_buffer_size: $(echo $line | awk -F':' '{print $13}')"
    echo "      myisam_sort_buffer_size: $(echo $line | awk -F':' '{print $14}')"
    echo "      mysql_innodb_buffer_pool_size: $(echo $line | awk -F':' '{print $15}' | sed 's/M//')"

done
