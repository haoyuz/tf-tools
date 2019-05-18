#!/bin/bash

# Build TensorFlow pip package from source and install.
# Prerequisite: Python, bazel 0.22

PYTHON="python3"
TF_HOME="${HOME}/tensorflow"
PIP_PATH="/tmp/tensorflow_pkg"
SAVE_PIP_PATH="${HOME}/tensorflow_pkg"

configure() {
  export TF_PYTHON_VERSION="${PYTHON}"
  export TF_NEED_CUDA=1
  export TF_CUDA_VERSION=10
  export TF_CUDNN_VERSION=7
  export CC_OPT_FLAGS='-mavx'
  export PYTHON_BIN_PATH=$(which ${TF_PYTHON_VERSION})
  export LD_LIBRARY_PATH="/usr/local/cuda:/usr/local/cuda/lib64:/usr/local/cuda/extras/CUPTI/lib64"
  export TF_CUDA_COMPUTE_CAPABILITIES=3.5,3.7,5.2,6.0,6.1,7.0

  yes "" | "${PYTHON_BIN_PATH}" configure.py
}

build_pip_package() {
  rm -f ${PIP_PATH}/*
  cd ${TF_HOME}

  bazel build -c opt --config=cuda //tensorflow/tools/pip_package:build_pip_package
  ./bazel-bin/tensorflow/tools/pip_package/build_pip_package ${PIP_PATH}
}

build_v2_pip_package() {
  rm -f ${PIP_PATH}/*
  cd ${TF_HOME}

  bazel build -c opt --config=cuda --config=v2 //tensorflow/tools/pip_package:build_pip_package
  ./bazel-bin/tensorflow/tools/pip_package/build_pip_package ${PIP_PATH}
}

install_tf_pip_package() {
  ${PYTHON} -m pip uninstall -y tensorflow
  ${PYTHON} -m pip install --force-reinstall ${PIP_PATH}/tensorflow-*.whl
}

# Save should happen only after install (to get git version tag)
# Possible to get directly from `git log` except when generated from copybara
save_tf_pip_package() {
  cd
  tf_git_version=$(${PYTHON} -c "import tensorflow as tf; print(tf.__git_version__)")
  mkdir -p ${SAVE_PIP_PATH}/${tf_git_version}
  cp ${PIP_PATH}/tensorflow-*.whl ${SAVE_PIP_PATH}/${tf_git_version}
}
