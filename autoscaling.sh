#!/bin/bash

TF_TOOLS_REPO="https://github.com/haoyuz/tf-tools.git"
TF_TOOLS_HOME="${HOME}/tf-tools"
TF_TOOLS_BRANCH="autoscaling"
TF_DOCKER_REPO="https://bitbucket.org/andrewor14/tf-docker"
TF_DOCKER_BRANCH="autoscaling"
TF_DOCKER_HOME="${HOME}/tf-docker"
EXP_DIR="${HOME}/experiments"
GCS_LOG_PATH="gs://haoyuzhang-tf-gpu-pip/autoscaling"

EXP_CONTROL_URL="10.0.0.101:8000/"
EXP_ID_FILE_NAME="experiment_id.txt"
HOSTS_FILE_NAME="hosts.txt"
CONTAINER_NAME="autoscalingtest"
NETWORK_NAME="autoscaling-net"

HOSTNAME="0.0.0.0"
MASTER_HOST="0.0.0.0"

log () {
  log_message=$1
  date_time=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[${date_time} autoscaling.sh] ${log_message}"
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
  log "Setting timezone to America/Los_Angeles"
  # Requires sudo
  ln -sf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime
}

control_run_or_exit() {
  cd ${EXP_DIR}
  # Remote old experiment ID and hosts file
  rm ${EXP_ID_FILE_NAME}
  rm ${HOSTS_FILE_NAME}

  log "Getting experiment ID and hosts file from ${EXP_CONTROL_URL}"
  wget "${EXP_CONTROL_URL}/${EXP_ID_FILE_NAME}"
  retval=$?
  if [[ $retval -ne 0 ]]; then
    log "ERROR: Cannot get experiment ID file"
    exit 101
  fi
  wget "${EXP_CONTROL_URL}/${HOSTS_FILE_NAME}"
  retval=$?
  if [[ $retval -ne 0 ]]; then
    log "ERROR: Cannot get hosts file"
    exit 101
  fi

  # Assuming experiment ID is a timestamp for approximate start time
  export EXPERIMENT_ID=$(cat "${EXP_ID_FILE_NAME}")
  log "Got experiment ID ${EXPERIMENT_ID}"
  date_time=$(date '+%Y%m%d%H%M%S')
  if [[ "${EXPERIMENT_ID}" -lt "${date_time}" ]]; then
    log "ERROR: Experiment ID expired. Must be larger than current timestamp."
    exit 102
  fi

  export MASTER_HOST=$(head -1 "${HOSTS_FILE_NAME}")
  if [[ "${MASTER_HOST}" == "${HOSTNAME}" ]]; then
    log "I am master!"
  fi
}

init() {
  log "Preparing environment..."
  set_timezone
  export HOSTNAME=$(hostname -i)
  ensure_code ${TF_TOOLS_HOME} ${TF_TOOLS_REPO} ${TF_TOOLS_BRANCH}
  ensure_code ${TF_DOCKER_HOME} ${TF_DOCKER_REPO} ${TF_DOCKER_BRANCH}

  mkdir -p ${EXP_DIR}
  rm -rf ${EXP_DIR}/*
}

build_docker_image() {
  cd ${EXP_DIR}
  log "Building docker image..."
  docker build -t autoscaling:latest -f ${TF_DOCKER_HOME}/Dockerfile .
}

execute_in_docker() {
  command=$1
  log "Executing the following command in docker"
  log "${command}"
  docker exec -it ${CONTAINER_NAME} bash -c "${command}"
}

cleanup() {
  docker rm -f $(docker ps -a -q)
  docker network rm ${NETWORK_NAME}
}

setup_vm_cluster() {
  log "Setup SSH between host VMs"
  ${TF_DOCKER_HOME}/scripts/enable_ssh_access.sh "${EXP_DIR}/${HOSTS_FILE_NAME}" ${HOME}/.ssh
}

setup_docker_cluster() {
  log "Clean up running docker instances"
  cleanup

  if [[ "${MASTER_HOST}" == "${HOSTNAME}" ]]; then
    log "On master node, build an overlay network, make everyone join it"
    ${TF_DOCKER_HOME}/scripts/build_overlay_network.sh "${EXP_DIR}/${HOSTS_FILE_NAME}"
  else
    log "On worker node, query the overlay network before trying to join it"
    until ssh -tt ${MASTER_HOST} "docker network ls | grep ${NETWORK_NAME}"; do
      sleep 1
    done
  fi

  log "Start containers attached to the overlay network"
  mkdir -p ${EXP_DIR}/container_hosts
  rm -rf ${EXP_DIR}/container_hosts/*
  docker run --name "${CONTAINER_NAME}" -dit --network=${NETWORK_NAME} --runtime=nvidia \
      -v ${EXP_DIR}/container_hosts:/root/container_hosts \
      -v ${EXP_DIR}/logs:/root/dev/logs \
      autoscaling

  cluster_size=$(wc -l < ${EXP_DIR}/${HOSTS_FILE_NAME})
  until [[ "$(wc -l < ${EXP_DIR}/container_hosts/hosts.txt)" == "${cluster_size}" ]]; do
    log "Find the container hostnames and make them accessible from within the container"
    ${TF_DOCKER_HOME}/scripts/get_container_hostnames.sh "${EXP_DIR}/${HOSTS_FILE_NAME}" ${EXP_DIR}/container_hosts

    container_cluster_size=$(wc -l < ${EXP_DIR}/container_hosts/hosts.txt)
    log "Container cluster size is ${container_cluster_size}, expecting ${cluster_size}"
    sleep 5
  done

  execute_in_docker "cd /root/dev/tf-docker/scripts; git pull; ./enable_ssh_access.sh /root/container_hosts/hosts.txt"
  if [[ "${MASTER_HOST}" == "${HOSTNAME}" ]]; then
    execute_in_docker "mpirun --allow-run-as-root --hostfile /root/container_hosts/hosts.txt -np 4 hostname"
  fi
}

run_experiment() {
  if [[ "${MASTER_HOST}" == "${HOSTNAME}" ]]; then
    execute_in_docker "cd /root/dev/models/deploy; git pull; ./run_experiment.sh"
  fi
}

upload_logs() {
  GCS_URL="${GCS_LOG_PATH}/${EXPERIMENT_ID}/logs"
  log "Upload logs to ${GCS_URL}"
  gsutil cp -r ${EXP_DIR}/logs "${GCS_LOG_PATH}/${EXPERIMENT_ID}/logs"
}

main() {
  init
  control_run_or_exit
  setup_vm_cluster

  build_docker_image
  setup_docker_cluster
  run_experiment
  upload_logs
}