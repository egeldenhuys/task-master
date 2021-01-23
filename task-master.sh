#!/bin/bash

# https://stackoverflow.com/a/246128
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

set -e

message_url_prefix=$1
task_name=$2
kill_hour_start=$3
kill_minute_start=$4
kill_hour_stop=$5
kill_minute_stop=$6
task_script=$7

state_dir=$DIR/state
task_retry_delay_seconds=300
watcher_script=$DIR/watcher.sh

mkdir -p "$state_dir"

task_last_exit_code_file=$state_dir/$task_name.last

set +e
task_last_exit_code=$(cat "$task_last_exit_code_file")
set -e

task_log_file=$state_dir/$task_name.log

function send_message() {
    local message="$1"
    echo "$message" | sed -z 's/\\n/\n/g'
    message=$(echo "$message" | tr " " "-")
    message=$(echo "$message" | sed -z 's/\n/%0A/g')
    message=$(echo "$message" | sed -z 's/\\n/%0A/g')
    curl --silent --retry 3 --retry-delay 30 "$message_url_prefix/$message" > /dev/null
}

if [ "$task_last_exit_code" = "0" ]; then
    send_message "Task $task_name has already been executed successfully."
    exit 0
fi

send_message "Starting Task Master for task $task_name"

$watcher_script "$message_url_prefix" "$task_name" $$ "$kill_hour_start" "$kill_minute_start" "$kill_hour_stop" "$kill_minute_stop" &
watcher_pid=$!

trap ctrl_c INT

function ctrl_c() {
    send_message "Killing:\nTask Master ($BASHPID)\nWatcher ($watcher_pid)\nTask $task_name"
    kill -n 15 $watcher_pid
    exit 130
}

trap cleanup SIGTERM
task_pid=-1

function cleanup() {
    send_message "Task master ($$) for task $task_name is being assualted by The Watcher.\nTask master is killing task with PID $task_pid"

    if [ ! "$task_pid" = "-1" ]; then
        kill -n 15 $task_pid
    fi

    exit 0
}

task_exit_code=1
while [ ! "$task_exit_code" = "0" ]; do
    send_message "Running task: $task_name..."

    set +e
    $task_script 2>&1 | tee "$task_log_file" &
    task_pid=$!
    wait $task_pid
    task_exit_code=$?
    set -e

    if [ "$task_exit_code" = "0" ]; then
        send_message "Task $task_name executed successfully."
        echo "0" > "$task_last_exit_code_file"
        exit 0
    else
        send_message "Task Log: $task_name \n $(tail "$task_log_file")"
        send_message "Task $task_name failed with exit code $task_exit_code. Retrying in $task_retry_delay_seconds seconds."
        sleep $task_retry_delay_seconds
    fi
done
