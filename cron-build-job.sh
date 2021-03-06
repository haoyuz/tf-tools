#!/bin/bash

TF_TOOLS_HOME="${HOME}/tf-tools"
# Python 3.6 virtual env should have already be prepared with TF dependencies
# (to prepare, maybe just install tf-nightly-gpu, and then uninstall TF)
#   add-apt-repository ppa:deadsnakes/ppa
#   apt-get install -y python3.6 python3.6-dev python3.6-venv
#   virtualenv -p python3.6 py36venv
PYTHON36_VENV="py36venv"
GCS_LOG_PATH="gs://haoyuzhang-tf-gpu-pip/logs"

# Checkout latest version of script
cd ${TF_TOOLS_HOME}
git pull

date_time=$(date '+%Y%m%d-%H%M%S')
tmp_log_file="/tmp/continuous-build.log"
gs_log_file="${GCS_LOG_PATH}/build-${date_time}"

if $(pgrep -f continuous-build.sh > /dev/null); then
  echo "Last cron job is still running." > /tmp/dummy.log
  gsutil cp /tmp/dummy.log "${gs_log_file}-blocked.log"
  exit 1
fi

source ${HOME}/${PYTHON36_VENV}/bin/activate

if bash ${TF_TOOLS_HOME}/continuous-build.sh &> ${tmp_log_file}; then
  gsutil cp ${tmp_log_file} "${gs_log_file}.log"
else
  gsutil cp ${tmp_log_file} "${gs_log_file}-failed.log"
fi
