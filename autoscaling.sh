#!/bin/bash

TF_TOOLS_HOME="${HOME}/tf-tools"
TF_DOCKER_HOME="${HOME}/tf-docker"
EXP_DIR="${HOME}/experiments"
GCS_LOG_PATH="gs://haoyuzhang-tf-gpu-pip/autoscaling"

EXP_CONTROL_URL="10.0.0.101:8000/"
EXP_ID_FILE_NAME="experiment_id.txt"
HOSTS_FILE_NAME="hosts.txt"
CONTAINER_NAME="autoscalingtest"

HOSTNAME="0.0.0.0"
IS_MASTER=0

log () {
  log_message=$1
  date_time=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[${date_time} ContinuousBuild] ${log_message}"
}

ensure_code() {
  path_to_code=$1
  repo_url=$2
  branch_name=$3
  [[ -d ${path_to_code} ]] || git clone ${code_url} ${path_to_code}
  cd ${path_to_code}
  git checkout .  # discard local changes (if any)
  git pull
  git checkout ${branch_name}
  cd -
}

set_timezone() {
  # Requires sudo
  ln -sf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime
}

control_run_or_exit() {
  cd ${EXP_DIR}
  # Remote old experiment ID and hosts file
  rm ${EXP_ID_FILE_NAME}
  rm ${HOSTS_FILE_NAME}

  # Try to get experiment ID and hosts file from a URL
  wget "${EXP_CONTROL_URL}/${EXP_ID_FILE_NAME}"
  retval=$?
  if [[ $retval -ne 0 ]]; then
    exit 101
  fi
  wget "${EXP_CONTROL_URL}/${HOSTS_FILE_NAME}"
  retval=$?
  if [[ $retval -ne 0 ]]; then
    exit 101
  fi

  # Assuming experiment ID is a timestamp showing the approximate start time.
  export EXPERIMENT_ID=$(cat "${EXP_ID_FILE_NAME}")
  date_time=$(date '+%Y%m%d%H%M%S')
  if [[ "${EXPERIMENT_ID}" -lt "${date_time}" ]]; then
    exit 102
  fi

  log "Get experiment ID ${EXPERIMENT_ID}"

  master=$(head -1 "${HOSTS_FILE_NAME}")
  if [[ "${master}" == "${HOSTNAME}" ]]; then
    IS_MASTER=1
    log "I am master!"
  fi
}

init() {
  log "Preparing environment..."
  set_timezone
  export HOSTNAME=$(hostname -i)
  ensure_code ${TF_TOOLS_HOME} "https://github.com/haoyuz/tf-tools.git" "autoscaling"
  ensure_code ${TF_DOCKER_HOME} "https://bitbucket.org/andrewor14/tf-docker" "autoscaling"

  mkdir -p ${EXP_DIR}
  rm -rf ${EXP_DIR}/*
}

build_docker_image() {
  cd ${EXP_DIR}
  log "Build docker image..."
  docker build -t autoscaling:latest -f src/autoscaling/Dockerfile .
}

execute_in_docker() {
  command=$1
  log "Executing the following command in docker"
  log "$command"
  docker exec -it ${CONTAINER_NAME} bash -c "${command}"
}

setup_cluster() {
  log "Clean up running docker instances"
  docker rm -f $(docker ps -a -q)

  log "Setup SSH between host VMs"
  ${TF_DOCKER_HOME}/scripts/enable_ssh_access.sh "${EXP_DIR}/${HOSTS_FILE_NAME}" ${HOME}/.ssh

  if [[ "$IS_MASTER" == 1 ]]; then
    log "On master node, build an overlay network, make everyone join it"
    ${TF_DOCKER_HOME}/scripts/build_overlay_network.sh "${EXP_DIR}/${HOSTS_FILE_NAME}"
  fi
  # other nodes should sleep and wait for signal?

  log "Start containers attached to the overlay network"
  mkdir -p ${EXP_DIR}/container_hosts
  docker run --name "${CONTAINER_NAME}" -dit --network=autoscaling-net --runtime=nvidia \
      -v ${EXP_DIR}/container_hosts:/root/container_hosts \
      -v ${EXP_DIR}/logs:/root/dev/logs \
      autoscaling

  log "Find the container hostnames and make them accessible from within the container"
  ${TF_DOCKER_HOME}/scripts/get_container_hostnames.sh "${EXP_DIR}/${HOSTS_FILE_NAME}" ${EXP_DIR}/container_hosts

  execute_in_docker "cd root/dev/tf-docker/scripts; git pull; ./enable_ssh_access.sh /root/container_hosts/hosts.txt"
  if [[ "$IS_MASTER" == "1" ]]; then
    execute_in_docker "mpirun --allow-run-as-root --hostfile /root/container_hosts/hosts.txt -np 4 hostname"
  fi
}

run_experiment() {
  if [[ "$IS_MASTER" == "1" ]]; then
    execute_in_docker "/root/dev/models/deploy/run_experiments.sh"
  fi
}

upload_logs() {
  log "Upload logs to GCS"
  gsutil cp -r ${EXP_DIR}/logs "${GCS_LOG_PATH}/${EXPERIMENT_ID}/logs"
}

main() {
  init
  control_run_or_exit

  build_docker_image
  setup_cluster
  run_experiment
  upload_logs
}