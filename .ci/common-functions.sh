docker-login() {
	log_info "Logging in as ${DOCKER_USER}"
	docker login ${DOCKER_REGISTRY} -u ${DOCKER_USER} -p ${DOCKER_PASS} || docker login -u ${DOCKER_USER} -p ${DOCKER_PASS}
}

build-manifest-cmd-for-tag() {
    # build the manifest command for a given docker tag
    local docker_tag=$1
    if [[ ${DOCKER_OFFICIAL} = true ]]; then
        docker_uri="${DOCKER_REGISTRY}/library/${DOCKER_IMAGE}"
    else
        docker_uri="${DOCKER_REGISTRY}/${DOCKER_NAMESPACE}/${DOCKER_IMAGE}"
    fi
    docker_uri=$(strip-uri ${docker_uri})

    docker_manifest_command="docker manifest create ${docker_uri}:${docker_tag}"
    for ARCH in ${SUPPORTED_ARCHITECTURES}; do
        if [[ ${DOCKER_OFFICIAL} = true ]]; then
            docker_official_uri=$(strip-uri ${DOCKER_REGISTRY}/${ARCH}/${DOCKER_IMAGE})
            docker_manifest_command="${docker_manifest_command} ${docker_official_uri}:${docker_tag}"
        fi

        if [[ ${DOCKER_OFFICIAL} = false ]]; then
            docker_manifest_command="${docker_manifest_command} ${docker_uri}:${ARCH}-${docker_tag}"
        fi
        
    done
    echo ${docker_manifest_command}
}

annotate-manifest-for-tag() {
    local manifest_tag=$1
    if [[ ${DOCKER_OFFICIAL} = true ]]; then
        docker_uri="${DOCKER_REGISTRY}/library/${DOCKER_IMAGE}"
    else
        docker_uri="${DOCKER_REGISTRY}/${DOCKER_NAMESPACE}/${DOCKER_IMAGE}"
    fi
    docker_uri=$(strip-uri ${docker_uri})

    docker_manifest_command=""
    for ARCH in ${SUPPORTED_ARCHITECTURES}; do
        if [[ ${DOCKER_OFFICIAL} = true ]]; then
            docker_official_uri=$(strip-uri ${DOCKER_REGISTRY}/${ARCH}/${DOCKER_IMAGE})
            docker_manifest_command="${docker_manifest_command} && docker manifest annotate ${docker_uri}:${manifest_tag} ${docker_official_uri}:${manifest_tag} --arch ${ARCH}"
        fi
        
        if [[ ${DOCKER_OFFICIAL} = false ]]; then
            docker_manifest_command="${docker_manifest_command} && docker manifest annotate ${docker_uri}:${manifest_tag} ${docker_uri}:${ARCH}-${manifest_tag} --arch ${ARCH}"
        fi
    done
    docker_manifest_command=$(echo ${docker_manifest_command} | sed 's/^\&*//')  # strip off all leading '&' characters
    echo ${docker_manifest_command}
}

push-manifest-for-tag() {
    manifest_tag=$1
    docker_uri=$(strip-uri ${DOCKER_REGISTRY}/${DOCKER_NAMESPACE}/${DOCKER_IMAGE})

    if [[ ${DOCKER_OFFICIAL} = true ]]; then
        docker_uri=$(strip-uri ${DOCKER_REGISTRY}/library/${DOCKER_IMAGE})
    fi
    docker_manifest_command="docker manifest push --purge ${docker_uri}:${manifest_tag}"
    echo ${docker_manifest_command}
}

strip-uri() {
    uri=$1
    # strip off all leading '/' characters, change `//` to `/`
    uri=$(echo ${uri} | sed 's/^\/*//;s/\/\//\//g')
    echo ${uri}
}

get_docker_arch() {
    # if docker is running get it from docker
    if docker ps > /dev/null 2>&1; then
        arch=$(docker version -f {{.Server.Arch}})
        # armv7l just returns 'arm'
        if [[ ${arch} == 'arm' ]]; then
            arch='armv7l'
        fi
    else
        # otherwise use this matrix to determine architecture
        arch=""
        case "$(uname -m)" in
            amd64|x86_64)    arch='amd64';;
            aarch64|arm64)   arch='arm64';;
            armhf|armv7l)    arch='armv7l';;
            s390x)           arch='s390x';;
            ppc64el|ppc64le) arch='ppc64le';;
            *) echo "Unsupported architecture $(uname -m)"; exit 1;;
        esac
    fi
    echo ${arch}
}

log_debug() {
  if [[ ${IS_DEBUG} == true ]]; then
    echo "DEBU: $*"
  fi
}

log_info() {
  echo "INFO: $*"
}

log_warn() {
  echo "WARN: $*"
}

log_err() {
  echo "ERRO: $*"
}
