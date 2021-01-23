#!/bin/bash

set -e

message_url_prefix=$1
task_name=$2
master_pid=$3
kill_hour_start=$4
kill_minute_start=$5
kill_hour_stop=$6
kill_minute_stop=$7


function send_message() {
    local message="$1"
    echo "$message"
    message=$(echo "$message" | tr " " "-")
    message=$(echo "$message" | sed -z 's/\n/%0A/g')
    message=$(echo "$message" | sed -z 's/\\n/%0A/g')
    curl --silent --retry 3 --retry-delay 30 "$message_url_prefix/$message" > /dev/null
}

function is_current_time_less_than() {
    local hour=$1
    local minute=$2
    local current_hour
    local current_minute

    current_hour="$(date +'%H')"
    current_minute="$(date +'%M')"

    if [ "$current_hour" -lt "$hour" ]; then
        return 0
    else
        if [ "$current_hour" -le "$hour" ]; then
            if [ "$current_minute" -lt "$minute" ]; then
                return 0
            fi
        fi
    fi

    return 1
}

function is_current_time_greater_than() {
    local hour=$1
    local minute=$2
    local current_hour
    local current_minute

    current_hour="$(date +'%H')"
    current_minute="$(date +'%M')"

    if [ "$current_hour" -gt "$hour" ]; then
        return 0
    else
        if [ "$current_hour" -ge "$hour" ]; then
            if [ "$current_minute" -ge "$minute" ]; then
                return 0
            fi
        fi
    fi

    return 1
}

while true; do
    if is_current_time_greater_than $kill_hour_start $kill_minute_start; then
        if is_current_time_less_than $kill_hour_stop $kill_minute_stop; then
            send_message "Killing master for task $task_name with PID $master_pid"
            kill -n 15 "$master_pid"
            exit 0
        fi
    fi

    sleep 10
done
