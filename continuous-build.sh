#!/bin/bash

# Continuously build TensorFlow pip packages and upload to Google Cloud Storage.
# Run this script in cron job.
# Retention policy for current GCS bucket is set to 30 days.

TF_TOOLS_HOME="${HOME}/tf-tools"
TF_V1_HOME="${HOME}/tensorflow_v1_build"
TF_V2_HOME="${HOME}/tensorflow_v2_build"
GCS_BUCKET="gs://tf-performance/tf_binary/hourly"
PIP_PATH="/tmp/tensorflow_pkg"

log () {
  log_message=$1
  date_time=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[${date_time} ContinuousBuild] ${log_message}"
}

ensure_tf_code() {
  path_to_code=$1
  [[ -d ${path_to_code} ]] || \
    git clone https://github.com/tensorflow/tensorflow.git ${path_to_code}
}

log "-------------------- Starting Continuous Build --------------------"

source ${TF_TOOLS_HOME}/build-and-install.sh

ensure_tf_code ${TF_V1_HOME}
ensure_tf_code ${TF_V2_HOME}

cd ${TF_V1_HOME} && git pull

# Get current commit hash Piper CL number (last word of commit message)
# Use <CL>-<CommitHash> as the directory name on GCS to save the package
git_hash=$(git rev-parse HEAD)
piper_cl=$(git log -1 | grep PiperOrigin-RevId | rev | cut -d " " -f1 | rev)
gcs_path="${GCS_BUCKET}/${piper_cl}-${git_hash}"

cd ${TF_V2_HOME}
git checkout master
git pull
git checkout ${git_hash}  # Make sure v2 build is at the same commit as v1

log "Source code at cl/${piper_cl} and commit=${git_hash}"

# Run configure only if the environment vars are not configured yet
[[ -z "${TF_CUDA_COMPUTE_CAPABILITIES}" ]] && configure

log "Build TensorFlow v1 pip package..."
TF_HOME=${TF_V1_HOME} build_pip_package
log "Upload to ${gcs_path}"
gsutil cp ${PIP_PATH}/tensorflow-*.whl ${gcs_path}/v1/
gsutil cp ${PIP_PATH}/tensorflow-*.whl ${GCS_BUCKET}/latest/v1/

# log "Build TensorFlow v2 pip package..."
# TF_HOME=${TF_V2_HOME} build_v2_pip_package
# log "Upload to ${gcs_path}"
# gsutil cp ${PIP_PATH}/tensorflow-*.whl ${gcs_path}/v2/
# gsutil cp ${PIP_PATH}/tensorflow-*.whl ${GCS_BUCKET}/latest/v2/

log "-------------------- Finishing Continuous Build --------------------"