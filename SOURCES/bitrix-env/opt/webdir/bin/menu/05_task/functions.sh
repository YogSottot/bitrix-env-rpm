BASE_DIR=/opt/webdir
BIN_DIR=$BASE_DIR/bin

. $BIN_DIR/bitrix_utils.sh || exit 1

task_menu=$BIN_DIR/menu/05_task

# get_text variables
[[ -f $task_menu/functions.txt  ]] && \
        . $task_menu/functions.txt

get_pool_tasks(){

    process_inf=$($bx_process_script -a list)
    process_err=$(echo "$process_inf" | grep '^error:' | sed -e "s/^error://")
    process_msg=$(echo "$process_inf" | grep '^message:' | sed -e "s/^message://")

    POOL_TASKS_LIST=$(echo "$process_inf" | \
        grep '^info:' | sed -e "s/info://" | \
        sort -t':' -k4 -nr)
    POOL_TASKS_COUNT=$(echo "$POOL_TASKS_LIST" | wc -l)

    [[ $DEBUG -gt 0 ]] && \
        echo "$(get_text "$T0001" "$POOL_TASKS_COUNT")"
}

print_pool_tasks(){
    filter_type=$1     # filter by task type (ex. monitor)
    filter_status=$2   # filter by task status (error, finished, interrupt)
    filter_days=$3     # filter by task date
    print_limit=$4     # limit output data for menu


    [[ -z "$POOL_TASKS_COUNT" ]] && get_pool_tasks


    # Menu text
    echo_type=$filter_type
    echo_status=$filter_status
    echo_days=$filter_days
    [[ -z "$filter_type" ]]     &&  echo_type="$T0002"
    [[ -z "$filter_status" ]]   && echo_status="$T0002"
    [[ -z "$filter_days" ]]     && echo_days="$T0002"
    [[ -z "$print_limit" ]]     && print_limit=10

    pool_filter_list="$POOL_TASKS_LIST"
    [[ -n "$filter_type" ]] && \
        pool_filter_list=$(echo "$pool_filter_list" | grep -i ":$filter_type")
    [[ -n "$filter_status" ]] && \
        pool_filter_list=$(echo "$pool_filter_list" | grep -i ":$filter_status")

    if [[ -n "$filter_days" ]]; then
        CT=$(date +%s)
        LIMIT=$(( 86400 * $filter_days ))
        IFS_BAK=$IFS
        IFS=$'\n'
        pool_filter_list2=
        for line in $pool_filter_list; do
            task_time=$(echo $line| awk -F':' '{print $4}')
            if [[ $(( $CT - $task_time )) -gt $LIMIT ]]; then
                pool_filter_list2="$pool_filter_list2
$line"
            fi
        done
        IFS=$IFS_BAK
        IFS_BAK=
        pool_filter_list="$pool_filter_list2"
    fi

    FILTERED_TASK_CNT=$(echo "$pool_filter_list" | grep -vc '^$')

    print_color_text "$T0003"
    echo "$T0004 $echo_type"
    echo "$T0005 $echo_status"
    echo "$T0006 $echo_days"

    printed_tasks=0
    if [[ $FILTERED_TASK_CNT -gt 0 ]]; then
        print_color_text "$(get_text "$T0001" "$FILTERED_TASK_CNT")"
        echo $MENU_SPACER
        printf "%-25s | %-25s | %15s | %s\n" "TaskID" "Started at" "Status" "Last Step"
        echo $MENU_SPACER

        IFS_BAK=$IFS
        IFS=$'\n'

        for line in $pool_filter_list; do
            task_id=$(echo $line| awk -F':' '{print $2}')      # task id
            task_time=$(echo $line| awk -F':' '{print $4}')    # task started at
            task_date=$(date -d @$task_time +"%d/%m/%Y %H:%M")
            task_status=$(echo $line| awk -F':' '{print $6}')  # task status
            task_step=$(echo $line| awk -F':' '{print $NF}')   # current operations

            if [[ $printed_tasks -lt $print_limit ]]; then
                printf "%-25s | %-25s | %15s | %s\n" \
                    "$task_id" "$task_date" "$task_status" "$task_step"
            fi
            printed_tasks=$(($printed_tasks+1))
        done

        IFS=$IFS_BAK
        IFS_BAK=
        echo $MENU_SPACER
    else
        print_color_text "$T0007" red
        echo
    fi
}

stop_task(){
    print_message "$T0008" "" "" task_id

    stop_task_inf=$($bx_process_script -a stop -t $task_id)
    stop_task_msg=$(echo "$stop_task_inf" | grep "message:" | sed -e 's/message://;')
    stop_task_err=$(echo "$stop_task_err" | grep "error:" | sed -e 's/error://;')
    stop_task_dat=$(echo "$stop_task_err" | grep "info:" | sed -e 's/info://;')

    if [[ -n "$stop_task_err" ]]; then
        print_color_text "$(get_text "$T0009" "$task_id")"
        print_message "$T0200" "$stop_task_msg" "" any_key
        return 1
    else
        POOL_TASKS_COUNT=
        print_message "$T0200" \
            "$(get_text "$T0010" "$task_id")" "" any_key
        return 0
    fi
}

clear_history() {
    clear
    print_message "$T0011" \
        "$T0012" "" task_clear_days 7
    print_message \
        "$T0013" "" "" task_clear_type

    print_pool_tasks "$task_clear_type" "" "$task_clear_days"
    if [[ $FILTERED_TASK_CNT -eq 0 ]]; then
        print_message "$T0200" "" "" any_key
        return 0
    fi

    print_message "$T0014" "" "" task_clear_answer 'n'
    if [[ $(echo "$task_clear_answer" | grep -iw "n") ]]; then
        TASK_MENU_SELECT=
    else
        stop_task_exe="$bx_process_script -a clean -d $task_clear_days"
        if [[ -n $task_clear_type ]]; then
            stop_task_exe=$stop_task_exe" -T $task_clear_type"
        fi
        [[ $DEBUG -gt 0 ]] && \
            echo "exec: $stop_task_exe"
        stop_task_inf=$($stop_task_exe)
        stop_task_msg=$(echo "$stop_task_inf" | grep "message:" | sed -e 's/message://;')
        stop_task_err=$(echo "$stop_task_err" | grep "error:" | sed -e 's/error://;')
        print_message "$T0200" "$stop_task_msg" "" any_key
        TASK_MENU_SELECT=
        POOL_TASKS_COUNT=
  fi
}

