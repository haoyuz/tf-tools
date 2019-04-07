#!/bin/bash

PYTHON=python3
TF_HOME="${HOME}/tensorflow"
TF_TOOLS_HOME="${HOME}/tf-tools"
TEST_OUTPUT="/tmp/bisect_output"
LOG_PREFIX="[TF_BISECT]"

. ${TF_TOOLS_HOME}/build-and-install.sh

test_command() {
  test_log=$1

  cd $HOME/repos/models
  ${PYTHON} -c "import tensorflow as tf; print('TF version:', tf.__version__); print('TF Git version:', tf.__git_version__)"

  PYTHONPATH=. \
  ${PYTHON} official/resnet/keras/keras_imagenet_main.py \
    --skip_eval --dtype=fp16 --enable_eager --enable_xla \
    --num_gpus=8 --batch_size=2048 \
    --train_steps=201 --alsologtostderr --synth &> ${test_log}
}

parse_output() {
  test_log=$1

  # {'num_batches':200, 'time_taken': 22.305864,'images_per_second': 9181.442114}
  line=$(cat "${test_log}" | grep "num_batches':200,")
  last_word=${line##* }  # after substitution: 9181.442114}
  int_in_last_word=${last_word%.*}  # after substitution: 9181

  # if the measured performance is less than 9000, exit with error
  if [[ "${int_in_last_word}" -lt "9350" ]]; then
    echo "${LOG_PREFIX} bad performance: ${int_in_last_word}"
    exit 1
  fi
  echo "${LOG_PREFIX} good performance: ${int_in_last_word}"
}

bisect_run() {
  echo "|||||||||||||||||||||||||||||||||"
  date
  cd ${TF_HOME}
  git_commit=$(git log --pretty=format:'%h' -n 1)
  echo "${LOG_PREFIX} ${git_commit} Build TensorFlow from source"

  mkdir -p ${TEST_OUTPUT}
  build_log="${TEST_OUTPUT}/${git_commit}_build.log"
  test_log="${TEST_OUTPUT}/${git_commit}_test.log"

  build_pip_package &> ${build_log}
  echo "${LOG_PREFIX} ${git_commit} Install TensorFlow from source"
  install_tf_pip_package 2>&1 >> ${build_log}
  echo "${LOG_PREFIX} ${git_commit} Run tests"
  test_command ${test_log}
  echo "${LOG_PREFIX} ${git_commit} Parse test output"
  parse_output ${test_log}
}

bisect_run
