#!/bin/bash

# Continuously build TensorFlow pip packages and upload to Google Cloud Storage.
# Run this script in cron job.
# Retention policy for current GCS bucket is set to 30 days.

# TensorFlow version to build. Either 1 or 2. Default 1.
TF_VER=${1:-1}

TF_TOOLS_HOME="${HOME}/tf-tools"
TF_HOME="${HOME}/tensorflow_v${TF_VER}_build"
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

ensure_tf_code ${TF_HOME}

cd ${TF_HOME} && git pull

# TODO: check out last commit before current hour in time, to make sure the v1
# and v2 builds are synced at the same commit

# Get current commit hash Piper CL number (last word of commit message)
# Use <CL>-<CommitHash> as the directory name on GCS to save the package
git_hash=$(git rev-parse HEAD)
piper_cl=$(git log -1 | grep PiperOrigin-RevId | rev | cut -d " " -f1 | rev)
gcs_path="${GCS_BUCKET}/${piper_cl}-${git_hash}"

log "Source code at cl/${piper_cl} and commit=${git_hash}"

# Run configure only if the environment vars are not configured yet
[[ -z "${TF_CUDA_COMPUTE_CAPABILITIES}" ]] && configure

log "Build TensorFlow v${TF_VER} pip package..."
TF_HOME=${TF_HOME} build_v${TF_VER}_pip_package
log "Upload to ${gcs_path}"
gsutil cp ${PIP_PATH}/tensorflow-*.whl ${gcs_path}/v${TF_VER}/
gsutil cp ${PIP_PATH}/tensorflow-*.whl ${GCS_BUCKET}/latest/v${TF_VER}/

log "-------------------- Finishing Continuous Build --------------------"
