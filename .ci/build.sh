#!/bin/bash
# set -exo pipefail

# ------------------------------------
#  ____   __   ____   __   _  _  ____ 
# (  _ \ / _\ (  _ \ / _\ ( \/ )/ ___)
#  ) __//    \ )   //    \/ \/ \\___ \
# (__)  \_/\_/(__\_)\_/\_/\_)(_/(____/
# ------------------------------------

# This script requires you to have a few environment variables set. As this is targeted
# to be used in a CICD environment, you should set these either via the Jenkins/Travis
# web-ui or in the `.travis.yml` or `pipeline` file respectfully 

# DOCKER_USER - Used for `docker login` to the private registry DOCKER_REGISTRY
# DOCKER_PASS - Password for the DOCKER_USER
# DOCKER_REGISTRY - Docker Registry to push the docker image and manifest to (defaults to docker.io)
# DOCKER_NAMESPACE - Docker namespace to push the docker image to (this is your username for DockerHub)
# DOCKER_ARCH - The CPU Architecture the docker image is being built on

source ./.ci/common-functions.sh > /dev/null 2>&1 || source ./ci/common-functions.sh > /dev/null 2>&1

# Default values
DOCKER_BUILD_ARGS=""
DOCKER_BUILD_OPTS=""
DOCKER_BUILD_PATH="."
DOCKER_OFFICIAL=false
DOCKER_PUSH=false
IS_DRY_RUN=false

usage() {
  echo -e "A build script for docker images to aid the publishing of multi-arch containers \n\n"
  echo "Options:"
  echo "    --build-args   Set build-time variables in a space separated string (i.e. --build-args \"FOO=bar BAR=foo\")"
  echo "    --build-opts   Set additonal build options supported by docker, separated by spaces (i.e. --build-opts \"--pull --no-cache\")"
  echo "-c, --context      Docker image build path to use (Default is '.')"
  echo "    --dry-run      Print out what will happen, do not execute"
  echo "-f, --file         Name of the Dockerfile (Default is 'PATH/Dockerfile')"
  echo "-i, --image        Name of the image and optionally a tag in the 'name:tag' format"
  echo "    --official     Mimic the official docker publish method for images in private registries"
  echo "    --push         Push the image to the specified DOCKER_REGISTRY and DOCKER_NAMESPACE"
  echo ""
  echo "Usage:"
  echo "${0} [-f|--file path/to/Dockerfile] --image example-docker-manifest:1.0.0-8-jdk-openj9-bionic [-c|--context .] [--build-args \"FOO=bar\"] [--build-opts \"--pull\"] [--push] [--official] [--dry-run]"
  echo ""
}

if [[ "$*" == "" ]] || [[ "$*" != *--image* ]]; then
  usage
  exit 1
fi

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -f|--file)
    DOCKERFILE=$2
    shift
    ;;
    -i|--image)
    DOCKER_IMAGE=$2
    shift
    ;;
    --build-args)
    DOCKER_BUILD_ARGS=$2
    shift
    ;;
    --official)
    DOCKER_OFFICIAL=true
    ;;
    --build-opts)
    DOCKER_BUILD_OPTS=$2
    shift
    ;;
    -c|--context)
    DOCKER_BUILD_PATH=$2
    shift
    ;;
    --push)
    DOCKER_PUSH=true
    ;;
    --dry-run)
    IS_DRY_RUN=true
    ;;
    *)
    echo "Unknown option: $key"
    return 1
    ;;
  esac
  shift
done

if [[ "${FORCE_CI}" == "true" ]] || ([[ "${GIT_BRANCH}" == "${RELEASE_BRANCH:-master}" ]] && [[ "${IS_PULL_REQUEST}" == "false" ]]); then

  # ------------------------------
  #  ____  ____  ____  _  _  ____ 
  # / ___)(  __)(_  _)/ )( \(  _ \
  # \___ \ ) _)   )(  ) \/ ( ) __/
  # (____/(____) (__) \____/(__)  
  # ------------------------------

  if [[ ${IS_DRY_RUN} = true ]]; then
    echo "INFO: Dry run executing, nothing will be pushed/run"
  fi

  # Default the Dockerfile name if not provided
  DOCKERFILE=${DOCKERFILE:-Dockerfile}

  # Get the Docker Architecture if not provided
  if [[ -z ${DOCKER_ARCH} ]]; then
    DOCKER_ARCH=$(docker version -f {{.Server.Arch}})
  fi

  # split the DOCKER_IMAGE into DOCKER_IMAGE_NAME DOCKER_TAG based on the delimiter, ':'
  IFS=":" read -r -a image_info <<< "$DOCKER_IMAGE"
  DOCKER_IMAGE_NAME=${image_info[0]}
  DOCKER_BUILD_TAG=${image_info[1]}

  if [[ -z ${DOCKER_BUILD_TAG} ]]; then
    # if the DOCKER_BUILD_TAG is not set, default to latest
    DOCKER_BUILD_TAG="latest"
  fi

  if [[ -n ${DOCKER_BUILD_ARGS} ]]; then
    # the docker build args are set, expand the build args into docker command
    expanded_build_args=""
    for arg in ${DOCKER_BUILD_ARGS}
    do
      expanded_build_args="${expanded_build_args} --build-arg ${arg}"
    done
    DOCKER_BUILD_ARGS=${expanded_build_args}
  fi

  # This uses DOCKER_USER and DOCKER_PASS to login to DOCKER_REGISTRY
  if [[ ! ${IS_DRY_RUN} = true ]]; then
    docker-login
  fi

  # # check if the image has already been published to the registry before pushing
  # is-published ${DOCKER_BUILD_TAG}

  # --------------------------------------------------------------------------
  #  ____  _  _  __  __    ____     __   __ _  ____    ____  _  _  ____  _  _ 
  # (  _ \/ )( \(  )(  )  (    \   / _\ (  ( \(    \  (  _ \/ )( \/ ___)/ )( \
  #  ) _ () \/ ( )( / (_/\ ) D (  /    \/    / ) D (   ) __/) \/ (\___ \) __ (
  # (____/\____/(__)\____/(____/  \_/\_/\_)__)(____/  (__)  \____/(____/\_)(_/
  # --------------------------------------------------------------------------

  if [[ ${DOCKER_OFFICIAL} = true ]]; then
    # mimic the official build format  i.e. registry/arch/image:tag
    DOCKER_REPO=${DOCKER_REGISTRY}/${DOCKER_ARCH}/${DOCKER_IMAGE_NAME}
    DOCKER_BUILD_TAG=${DOCKER_BUILD_TAG}
    DOCKER_URI="${DOCKER_REPO}:${DOCKER_BUILD_TAG}"
  fi
  
  if [[ ${DOCKER_OFFICIAL} = false ]]; then
    # build image so it is compatible with dockerhub deployment  i.e. registry/namespace/image:arch-tag
    DOCKER_REPO=${DOCKER_REGISTRY}/${DOCKER_NAMESPACE}/${DOCKER_IMAGE_NAME}
    DOCKER_BUILD_TAG=${DOCKER_ARCH}-${DOCKER_BUILD_TAG}
    DOCKER_URI="${DOCKER_REPO}:${DOCKER_BUILD_TAG}"
  fi

  DOCKER_URI=$(strip-uri ${DOCKER_URI})

  echo "INFO: Building ${DOCKER_URI} using ${DOCKER_BUILD_PATH}/${DOCKERFILE}"
  if [[ ! ${IS_DRY_RUN} = true ]]; then
    cd ${DOCKER_BUILD_PATH} && \
    docker build --pull ${DOCKER_BUILD_ARGS} ${DOCKER_BUILD_OPTS} -t ${DOCKER_URI} -f ${DOCKERFILE} .
  fi

  if [[ ${DOCKER_PUSH} = true ]]; then
    # push the built image to the registry
    echo "INFO: Pushing ${DOCKER_URI}"
    if [[ ! ${IS_DRY_RUN} = true ]]; then
      docker push ${DOCKER_URI}
    fi
  fi

fi
