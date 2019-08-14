#!/bin/bash

TF_TOOLS_HOME="${HOME}/tf-tools"
HOSTNAME=$(hostname)
GCS_LOG_PATH="gs://haoyuzhang-tf-gpu-pip/autoscaling/cron-${HOSTNAME}"

# Checkout latest version of script
cd ${TF_TOOLS_HOME}
git pull
git checkout autoscaling

date_time=$(date '+%Y%m%d-%H%M%S')
tmp_log_file="/tmp/cron-autoscaling.log"
gs_log_file="${GCS_LOG_PATH}/run-${date_time}"

if $(pgrep -f autoscaling.sh > /dev/null); then
  echo "Last cron job is still running." > /tmp/dummy.log
  gsutil cp /tmp/dummy.log "${gs_log_file}-blocked.log"
  exit 1
fi

if bash ${TF_TOOLS_HOME}/autoscaling.sh &> ${tmp_log_file}; then
  gsutil cp ${tmp_log_file} "${gs_log_file}.log"
else
  gsutil cp ${tmp_log_file} "${gs_log_file}-failed.log"
fi
