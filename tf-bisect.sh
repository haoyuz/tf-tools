#!/usr/bin/env bash

. build-and-install.sh

PYTHON=python3
BISECT_LOG="${HOME}/bisect_log.txt"
TEST_OUTPUT="/tmp/test_output.log"

test_command() {
  cd $HOME/repos/models

  ${PYTHON} -c "import tensorflow as tf; print('TF version:', tf.__version__); print('TF Git version:', tf.__git_version__)"

  TF_GPU_THREAD_MODE='gpu_private' PYTHONPATH=. \
  ${PYTHON} official/resnet/keras/keras_imagenet_main.py \
    --skip_eval --dtype=fp16 --enable_eager --enable_xla \
    --num_gpus=8 --batch_size=2048 \
    --train_steps=210 --alsologtostderr --synth &> ${TEST_OUTPUT}
}

parse_output() {
  # {'num_batches':200, 'time_taken': 22.305864,'images_per_second': 9181.442114}
  cat "${TEST_OUTPUT}"
  line=$(cat "${TEST_OUTPUT}" | grep "num_batches':200,")
  last_word=${line##* }  # after substitution: 9181.442114}
  int_in_last_word=${last_word%.*}  # after substitution: 9181

  # if the measured performance is less than 9000, exit with error
  if [[ "${int_in_last_word}" -lt "9000" ]]; then
    echo "[BISECT] bad performance: ${int_in_last_word}"
    exit 1
  fi
  echo "[BISECT] good performance: ${int_in_last_word}"
}

bisect_run() {
  echo "[BISECT] Build and install TensorFlow from source"
  cd ${HOME}/tensorflow
  build_pip_package
  install_tf_pip_package
  cd

  echo "[BISECT] Run tests"
  test_command

  echo "[BISECT] Parse test output"
  parse_output
}

echo "|||||||||||||||||||||||||||||||||" >> ${BISECT_LOG}
date >> ${BISECT_LOG}
bisect_run >> ${BISECT_LOG} 2>&1