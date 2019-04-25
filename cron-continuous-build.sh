#!/bin/bash

TF_TOOLS_HOME="${HOME}/tf-tools"
GCS_LOG_PATH="gs://haoyuzhang-tf-gpu-pip/logs"

date_time=$(date '+%Y-%m-%d-%H-%M-%S')
tmp_log_file="/tmp/continuous-build.log"
gs_log_file="${GCS_LOG_PATH}/build-${date_time}.log"

pid=$(pgrep -f cron-continuous-build.sh)
if $pid > /dev/null; then
  echo "Last cron job still running. pid=$pid" > /tmp/dummy.log
  gsutil cp /tmp/dummy.log ${gs_log_file}
  exit 1
fi

bash ${TF_TOOLS_HOME}/continuous-build.sh &> ${tmp_log_file}
gsutil cp ${tmp_log_file} ${gs_log_file}