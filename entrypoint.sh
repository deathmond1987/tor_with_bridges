#!/usr/bin/env bash
#set -x
set -euo pipefail
## colors
reset="\033[0m"
red="\033[0;31m"
green="\033[0;32m"
white="\033[0;37m"
tan="\033[0;33m"

info() { printf "${white}%s${reset}\n" "$@"
}
success() { printf "${green}%s${reset}\n" "$@"
}
error() { >&2 printf "${red}✖ %s${reset}\n" "$@"
}
warn() { printf "${tan}%s${reset}\n" "$@"
}

echo '    __                                __           __                    ____    '
echo '   / /_____  _____   _________  _____/ /_______   / /_  __  ______  ____/ / /__  '
echo '  / __/ __ \/ ___/  / ___/ __ \/ ___/ //_/ ___/  / __ \/ / / / __ \/ __  / / _ \ '
echo ' / /_/ /_/ / /     (__  ) /_/ / /__/ ,< (__  )  / /_/ / /_/ / / / / /_/ / /  __/ '
echo ' \__/\____/_/     /____/\____/\___/_/|_/____/  /_.___/\__,_/_/ /_/\__,_/_/\___/  '

## variables for this script
TOR_CONFIG_FILE=${DATA_DIR}/torrc
BRIDGE_FILE=${DATA_DIR}/torrc_bridges
LOCK_FILE=${DATA_DIR}/.lock

## tor config default values
SOCKS_IP=${SOCKS_IP:=127.0.0.1}
SOCKS_PORT=${SOCKS_PORT:=9050}
SOCKS_ACCEPT=${SOCKS_ACCEPT:=}
SOCKS_REJECT=${SOCKS_REJECT:=}
EXIT_RELAY=${EXIT_RELAY:=0}
HTTPS_PROXY=${HTTPS_PROXY:=}
HTTPS_PROXY_CREDS=${HTTPS_PROXY_CREDS:=}
## set tor relay scanner values
NUM_RELAYS=${NUM_RELAYS:=100}
MIN_RELAYS=${MIN_RELAYS:=1}
RELAY_TIMEOUT=${RELAY_TIMEOUT:=3}

## remove tor config file if exist
if [[ -f "${TOR_CONFIG_FILE}" ]]; then  
    warn "removing old config"
    rm -f "${TOR_CONFIG_FILE}"
fi

## remove file with list of bridges if exist
if [[ -f "${BRIDGE_FILE}" ]]; then
    warn "removing old bridge config"
    rm -f "${BRIDGE_FILE}"
fi

### remove cached entry guards
### or not...
#if [[ -f /home/nonroot/.tor/state ]]; then
#    rm -f /home/nonroot/.tor/state
#    warn "tor state file removed"
#fi

map_user(){
    ## https://github.com/magenta-aps/docker_user_mapping/blob/master/user-mapping.sh
    ## https://github.com/linuxserver/docker-baseimage-alpine/blob/3eb7146a55b7bff547905e0d3f71a26036448ae6/root/etc/cont-init.d/10-adduser
    ## https://github.com/haugene/docker-transmission-openvpn/blob/master/transmission/userSetup.sh

    ## Set puid & pgid to run container, fallback to defaults
    PUID=${PUID:-1000}
    PGID=${PGID:-1001}

    ## If uid or gid is different to existing modify nonroot user to suit
    if [ ! "$(id -u nonroot)" -eq "$PUID" ]; then usermod -o -u "$PUID" nonroot ; fi
    if [ ! "$(id -g nonroot)" -eq "$PGID" ]; then groupmod -o -g "$PGID" nonroot ; fi
    warn "Tor set to run as nonroot with uid:$(id -u nonroot) & gid:$(id -g nonroot)"

    ## Make sure volumes directories match nonroot
    chown -R nonroot:nonroot \
        "${DATA_DIR}"
    warn "Enforced ownership of ${DATA_DIR} to nonroot:nonroot"

    ## Make sure volume permissions are correct
    chmod -R go=rX,u=rwX \
        "${DATA_DIR}"
    warn "Enforced permissions for ${DATA_DIR} to go=rX & u=rwX"

    ## Export to the rest of the bash script
    export PUID
    export PGID
}

tor_config () {
    ## set SocksPort value to conf file
    echo "SocksPort $SOCKS_IP:$SOCKS_PORT" >> "${TOR_CONFIG_FILE}"
 
    ## if socks policy not null - set sockspolicy
    if [[ ! -z "${SOCKS_ACCEPT}" ]]; then
        echo "SocksPolicy accept ${SOCKS_ACCEPT}" >> "${TOR_CONFIG_FILE}"
    fi
    if [[ ! -z "${SOCKS_REJECT}" ]]; then
        echo "SocksPolicy reject ${SOCKS_REJECT}" >> "${TOR_CONFIG_FILE}"
    fi
 
    ## set exit relay value
    echo "ExitRelay $EXIT_RELAY" >> "${TOR_CONFIG_FILE}"
    echo "%include $BRIDGE_FILE" >> "${TOR_CONFIG_FILE}"

    if [[ ! -z "${HTTPS_PROXY}" ]]; then
        echo  "HTTPSProxy ${HTTPS_PROXY}" >> "${TOR_CONFIG_FILE}"
    fi
    if [[ ! -z "${HTTPS_PROXY_CREDS}" ]]; then
        echo "HTTPSProxyAuthenticator ${HTTPS_PROXY_CREDS}" >> "${TOR_CONFIG_FILE}"
    fi
}

print_config () {
    ## print info about config sets
    info "CONFIG:"
    warn "--------------------------------------------------------------------"
    warn "tor config:"
    info "  SocksPort listen on ${SOCKS_IP}:${SOCKS_PORT}"
    if [[ ! -z "${SOCKS_ACCEPT}" ]]; then
        info "  SocksPolicy accept set to ${SOCKS_ACCEPT}"
    fi
    info "  set exit relay to $EXIT_RELAY"
    if [[ ! -z "${SOCKS_REJECT}" ]]; then
        info "  SocksPolicy reject set to ${SOCKS_REJECT}"
    fi    

    if [[ ! -z "${HTTPS_PROXY}" ]]; then
        info "  HTTPSProxy set to ${HTTPS_PROXY}"
    fi
    if [[ ! -z "${HTTPS_PROXY_CREDS}" ]]; then
        info "  HTTPSProxyAuthenticator set to $(echo ${HTTPS_PROXY_CREDS} | sed 's/:.*$/:*****/')"
    fi
    warn "scanner config:"
    info "  min relays to find set to ${MIN_RELAYS}"
    info "  timeout relay check set to ${RELAY_TIMEOUT}"
    info "  check simultaneously bridges availability set to ${NUM_RELAYS}"
    if [[ ! -z "${PROXY_FOR_SCANNER}" ]]; then
        info "  scanner proxy set to ${PROXY_FOR_SCANNER}"
    fi
    warn "--------------------------------------------------------------------"
}

relay_scan () {
    ## creating lock file to temporary disable healthcheck
    touch "${LOCK_FILE}"

    ## searching open port from bridge list with tor-relay-scanner by valdikSS
    ## and write founded list to file
    while [ ! -s "${BRIDGE_FILE}" ]; do
        tor-relay-scanner --torrc \
                          -n "${NUM_RELAYS}" \
                          -g "${MIN_RELAYS}" \
                          --timeout "${RELAY_TIMEOUT}" > "${BRIDGE_FILE}"
    done
    ## remove lock file
    rm -f "${LOCK_FILE}"
    ## print min relays founded info
    success "number of relays scanner found: $(( $(wc -l < ${BRIDGE_FILE}) - 1 ))"
}

main () {
    tor_config
    print_config
    map_user
    relay_scan
     ## Display Tor version & torrc in log
    tor --version
    ## Execute dockerfile CMD as nonroot alternate gosu                                                                                                                           "
    su-exec "${PUID}:${PGID}" "$@"
}

main "$@"
