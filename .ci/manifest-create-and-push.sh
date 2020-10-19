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
# SUPPORTED_ARCHITECTURES - Which architectures the docker image supports and manifests will be generated for

source ./.ci/common-functions.sh > /dev/null 2>&1 || source ./ci/common-functions.sh > /dev/null 2>&1

IMAGE_VERSION=""        # The version of the image that will be used for the manifest
IMAGE_VARIANT=""        # The variant tag that will be used for the creation of the manifest, mapping all arch images to
LATEST=false            # Flag set if the docker manifest should include the latest image (usually the most verbose default variant/tag)
DOCKER_OFFICIAL=false   # mimic the official docker publish method for images in private registries

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -i|--image)
        DOCKER_IMAGE_NAME=$2
        shift
        ;;
        -v|--image-version)
        IMAGE_VERSION=$2
        shift
        ;;
        --variant)
        IMAGE_VARIANT=$2
        shift
        ;;
        -l|--latest)
        LATEST=true
        ;;
        -o|--official)
        DOCKER_OFFICIAL=true
        ;;
        *)
        echo "Unknown option: $key"
        return 1
        ;;
    esac
    shift
done

# Only build on master branch and NOT PR
if [[ "${GIT_BRANCH}" == "master" ]] && [[ "${IS_PULL_REQUEST}" == "false" ]]; then
    
    # ------------------------------
    #  ____  ____  ____  _  _  ____ 
    # / ___)(  __)(_  _)/ )( \(  _ \
    # \___ \ ) _)   )(  ) \/ ( ) __/
    # (____/(____) (__) \____/(__)  
    # ------------------------------

    DOCKER_TAG=""  # A unique tag for our docker image using the {image_version}-{image_variant}

    if [[ -n ${IMAGE_VERSION} ]]; then
        # the IMAGE_VERSION is set, update vars
        DOCKER_TAG=${IMAGE_VERSION}
    fi

    if [[ -n ${IMAGE_VARIANT} ]]; then
        # the IMAGE_VARIANT is set, append the variant to DOCKER_TAG
        DOCKER_TAG=${DOCKER_TAG}-${IMAGE_VARIANT}
    fi
    
    DOCKER_TAG=$(echo ${DOCKER_TAG} | sed 's/^-*//')  # strip off all leading '-' characters

    # This uses DOCKER_USER and DOCKER_PASS to login to DOCKER_REGISTRY
    docker-login

    # Pull each of our docker images on the supported architectures
    for ARCH in ${SUPPORTED_ARCHITECTURES}; do
        if [[ ${DOCKER_OFFICIAL} = true ]]; then
            DOCKER_REPO=${DOCKER_REGISTRY}/${ARCH}/${DOCKER_IMAGE_NAME}
            DOCKER_PULL_TAG=${DOCKER_TAG}  # pull registry/arch/image:tag
            DOCKER_PULL_LATEST=latest
        fi

        if [[ ${DOCKER_OFFICIAL} = false ]]; then
            DOCKER_REPO=${DOCKER_REGISTRY}/${DOCKER_NAMESPACE}/${DOCKER_IMAGE_NAME}
            DOCKER_PULL_TAG=${ARCH}-${DOCKER_TAG}  # pull registry/namespace/image:arch-tag
            DOCKER_PULL_LATEST=${ARCH}-latest
        fi

        DOCKER_REPO=$(echo ${DOCKER_REPO} | sed 's/^\/*//')  # strip off all leading '/' characters

        if [[ -n ${IMAGE_VERSION} || -n ${IMAGE_VARIANT} ]]; then
            # the IMAGE_VERSION or the IMAGE_VARIANT have been set, so pull the specifed image
            echo "INFO: Pulling ${DOCKER_REPO}:${DOCKER_PULL_TAG}"
            docker pull ${DOCKER_REPO}:${DOCKER_PULL_TAG}
        fi
        
        if [[ ${LATEST} = true ]]; then
            # the latest flag has been set, pull the latest image
            echo "INFO: Pulling ${DOCKER_REPO}:${DOCKER_PULL_LATEST}"
            docker pull ${DOCKER_REPO}:${DOCKER_PULL_LATEST}
        fi
    done

    # -----------------------------------------------------------------------------------
    #  _  _   __   __ _  __  ____  ____  ____  ____     ___  ____  ____   __  ____  ____ 
    # ( \/ ) / _\ (  ( \(  )(  __)(  __)/ ___)(_  _)   / __)(  _ \(  __) / _\(_  _)(  __)
    # / \/ \/    \/    / )(  ) _)  ) _) \___ \  )(    ( (__  )   / ) _) /    \ )(   ) _) 
    # \_)(_/\_/\_/\_)__)(__)(__)  (____)(____/ (__)    \___)(__\_)(____)\_/\_/(__) (____)
    # -----------------------------------------------------------------------------------

    # Create the manifest for our DOCKER_TAG
    if [[ -n ${IMAGE_VERSION} || -n ${IMAGE_VARIANT} ]]; then
        # the IMAGE_VERSION or the IMAGE_VARIANT have been set, so build the manifest
        docker_manifest="$(build-manifest-cmd-for-tag ${DOCKER_TAG})"
        # Run the docker_manifest string
        eval "${docker_manifest}"
    fi

    if [[ ${LATEST} = true ]]; then
        # create the latest manifest if the LATEST flag is true
        docker_manifest="$(build-manifest-cmd-for-tag latest)"
        # Run the docker_manifest string
        eval "${docker_manifest}"
    fi

    # ---------------------------------------------------------------------------------------------
    #  _  _   __   __ _  __  ____  ____  ____  ____     __   __ _  __ _   __  ____  __  ____  ____ 
    # ( \/ ) / _\ (  ( \(  )(  __)(  __)/ ___)(_  _)   / _\ (  ( \(  ( \ /  \(_  _)/ _\(_  _)(  __)
    # / \/ \/    \/    / )(  ) _)  ) _) \___ \  )(    /    \/    //    /(  O ) )( /    \ )(   ) _) 
    # \_)(_/\_/\_/\_)__)(__)(__)  (____)(____/ (__)   \_/\_/\_)__)\_)__) \__/ (__)\_/\_/(__) (____)
    # ---------------------------------------------------------------------------------------------

    # Annotate the manifest for our DOCKER_TAG
    if [[ -n ${IMAGE_VERSION} || -n ${IMAGE_VARIANT} ]]; then
        # the IMAGE_VERSION or the IMAGE_VARIANT have been set, so annotate the manifest
        manifest_annotate=$(annotate-manifest-for-tag ${DOCKER_TAG})
        # Run the manifest_annotate string
        eval "${manifest_annotate}"
    fi

    if [[ ${LATEST} = true ]]; then
        # create the latest manifest if the LATEST flag is true
        manifest_annotate=$(annotate-manifest-for-tag "latest")
        eval "${manifest_annotate}"
    fi

    # ---------------------------------------------------------------------------------------------
    #  _  _   __   __ _  __  ____  ____  ____  ____    ____  _  _  ____  _  _ 
    # ( \/ ) / _\ (  ( \(  )(  __)(  __)/ ___)(_  _)  (  _ \/ )( \/ ___)/ )( \
    # / \/ \/    \/    / )(  ) _)  ) _) \___ \  )(     ) __/) \/ (\___ \) __ (
    # \_)(_/\_/\_/\_)__)(__)(__)  (____)(____/ (__)   (__)  \____/(____/\_)(_/
    # ---------------------------------------------------------------------------------------------

    # Push the manifest for our DOCKER_TAG
    if [[ -n ${IMAGE_VERSION} || -n ${IMAGE_VARIANT} ]]; then
        # the IMAGE_VERSION or the IMAGE_VARIANT have been set, so push the manifest
        manifest_push=$(push-manifest-for-tag ${DOCKER_TAG})
        # Run the manifest_push string
        eval "${manifest_push}"
    fi

    if [[ ${LATEST} = true ]]; then
        # push latest manifest if the LATEST flag is true
        manifest_push=$(push-manifest-for-tag "latest")
        eval "${manifest_push}"
    fi

fi
