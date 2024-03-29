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
DOCKER_IMAGE=""
DOCKER_OFFICIAL=false
IS_DRY_RUN=false

usage() {
  echo -e "A docker push script that can be used when tesing an image prior to uploading \n\n"
  echo "Options:"
  echo "    --dry-run      Print out what will happen, do not execute"
  echo "-i, --image        The name of the image to push in the 'name:tag' format"
  echo "    --official     Mimic the official docker publish method for images in private registries"
  echo ""
  echo "Usage:"
  echo "${0} -i|--image example-docker-manifest:1.0.0-8-jdk-openj9-bionic [--official] [--dry-run]"
  echo ""
}

if [[ "$*" == "" ]] || [[ "$*" != *--image* ]]; then
  usage
  exit 1
fi

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -i|--image)
    DOCKER_IMAGE=$2
    shift
    ;;
    --official)
    DOCKER_OFFICIAL=true
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
    log_warn "Dry run executing, nothing will be pushed/run"
  fi

  # Get the Docker Architecture if not provided
  if [[ -z ${DOCKER_ARCH} ]]; then
    DOCKER_ARCH=$(get_docker_arch)
    if [[ "${DOCKER_ARCH}" == *"Unsupported architecture"* ]]; then
      log_err "${DOCKER_ARCH}, exiting"
      exit 1
    fi
  fi

  # split the DOCKER_IMAGE into DOCKER_IMAGE_NAME DOCKER_TAG based on the delimiter, ':'
  IFS=":" read -r -a image_info <<< "$DOCKER_IMAGE"
  DOCKER_IMAGE_NAME=${image_info[0]}
  DOCKER_TAG=${image_info[1]}
  
  if [[ -z ${DOCKER_TAG} ]]; then
    # if the DOCKER_TAG is not set, default to latest
    DOCKER_TAG="latest"
  fi

  # This uses DOCKER_USER and DOCKER_PASS to login to DOCKER_REGISTRY
  if [[ ! ${IS_DRY_RUN} = true ]]; then
    docker-login
  fi

  # ------------------------
  #  ____  _  _  ____  _  _ 
  # (  _ \/ )( \/ ___)/ )( \
  #  ) __/) \/ (\___ \) __ (
  # (__)  \____/(____/\_)(_/
  # ------------------------

  if [[ ${DOCKER_OFFICIAL} = true ]]; then
    # mimic the official build format  i.e. registry/arch/image:tag
    DOCKER_REPO=${DOCKER_REGISTRY}/${DOCKER_ARCH}/${DOCKER_IMAGE_NAME}
    DOCKER_TAG=${DOCKER_TAG}
    DOCKER_URI="${DOCKER_REPO}:${DOCKER_TAG}"
  fi
  
  if [[ ${DOCKER_OFFICIAL} = false ]]; then
    # build image so it is compatible with dockerhub deployment  i.e. registry/namespace/image:arch-tag
    DOCKER_REPO=${DOCKER_REGISTRY}/${DOCKER_NAMESPACE}/${DOCKER_IMAGE_NAME}
    DOCKER_TAG=${DOCKER_ARCH}-${DOCKER_TAG}
    DOCKER_URI="${DOCKER_REPO}:${DOCKER_TAG}"
  fi

  DOCKER_URI=$(strip-uri ${DOCKER_URI})

  # push the built image to the registry
  log_info "Pushing ${DOCKER_URI}"
  if [[ ! ${IS_DRY_RUN} = true ]]; then
    docker push ${DOCKER_URI}
  fi

fi
