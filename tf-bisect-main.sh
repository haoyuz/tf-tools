#!/bin/bash

TF_TOOLS_HOME=${HOME}/tf-tools
TF_HOME=${HOME}/tensorflow

. ${TF_TOOLS_HOME}/build-and-install.sh

good_rev=$1
bad_rev=$2

cd ${TF_HOME}
git bisect reset

echo "[TF_BISECT] Configure TensorFlow source code"
configure

git bisect start
git bisect bad ${bad_rev}
git bisect good ${good_rev}
git bisect run ${TF_TOOLS_HOME}/tf-bisect.sh
