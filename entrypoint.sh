#!/usr/bin/env bash
set -euo pipefail

## debug first
DEBUG=${DEBUG:=}
if [ ! -z ${DEBUG} ]; then
    ## set print debug if DEBUG enabled
    set -xv
fi

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

## just logo
echo '    __                                __           __                    ____    '
echo '   / /_____  _____   _________  _____/ /_______   / /_  __  ______  ____/ / /__  '
echo '  / __/ __ \/ ___/  / ___/ __ \/ ___/ //_/ ___/  / __ \/ / / / __ \/ __  / / _ \ '
echo ' / /_/ /_/ / /     (__  ) /_/ / /__/ ,< (__  )  / /_/ / /_/ / / / / /_/ / /  __/ '
echo ' \__/\____/_/     /____/\____/\___/_/|_/____/  /_.___/\__,_/_/ /_/\__,_/_/\___/  '
echo ''

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
TOR_CONTROL_PORT=${TOR_CONTROL_PORT:=}
HTTP_TUNNEL_PORT=${HTTP_TUNNEL_PORT:=}
EXCLUDE_EXIT_NODES=${EXCLUDE_EXIT_NODES:=}

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

    ## same but reject
    if [[ ! -z "${SOCKS_REJECT}" ]]; then
        echo "SocksPolicy reject ${SOCKS_REJECT}" >> "${TOR_CONFIG_FILE}"
    fi

    ## set tor control port
    if [[ ! -z "${TOR_CONTROL_PORT}" ]]; then
        echo "ControlPort 0.0.0.0:${TOR_CONTROL_PORT}" >> "${TOR_CONFIG_FILE}"
        ## gen random password
        PASS_GEN=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32; echo)
        ## use PASSWORD variable. if empty - use previous gen password 
        PASSWORD=${PASSWORD:=$PASS_GEN}
        ## get password hash
        HASH_PASS=$(tor --hash-password $PASSWORD | tail -n1)
        ## set hash password to config
        echo "HashedControlPassword ${HASH_PASS}" >> "${TOR_CONFIG_FILE}"
    fi

    ## set exit relay value
    echo "ExitRelay $EXIT_RELAY" >> "${TOR_CONFIG_FILE}"

    ## add include for file with bridge list
    echo "%include $BRIDGE_FILE" >> "${TOR_CONFIG_FILE}"

    ## set tor use external proxe
    if [[ ! -z "${HTTPS_PROXY}" ]]; then
        echo  "HTTPSProxy ${HTTPS_PROXY}" >> "${TOR_CONFIG_FILE}"
    fi

    ## set external proxy credentials
    if [[ ! -z "${HTTPS_PROXY_CREDS}" ]]; then
        echo "HTTPSProxyAuthenticator ${HTTPS_PROXY_CREDS}" >> "${TOR_CONFIG_FILE}"
    fi

    ## set array of excluded exit nodes
    if [[ ! -z "${EXCLUDE_EXIT_NODES}" ]]; then
        echo "ExcludeExitNodes ${EXCLUDE_EXIT_NODES}" >> "${TOR_CONFIG_FILE}"
    fi 

    ## today tor can be simple proxy
    if [[ ! -z "${HTTP_TUNNEL_PORT}" ]]; then
        echo "HTTPTunnelPort 0.0.0.0:${HTTP_TUNNEL_PORT}" >> "${TOR_CONFIG_FILE}"
    fi
}

print_config () {
    ## print info about config sets
    info "CONFIG:"
    warn "------------------------------------------------------------------------------"
    warn "tor config:"
    info "  SocksPort listen on ${SOCKS_IP}:${SOCKS_PORT}"
    if [[ ! -z "${SOCKS_ACCEPT}" ]]; then
        info "  SocksPolicy accept set: ${SOCKS_ACCEPT}"
    fi
    info "  exit relay: $EXIT_RELAY"
    if [[ ! -z "${SOCKS_REJECT}" ]]; then
        info "  SocksPolicy reject set: ${SOCKS_REJECT}"
    fi    

    if [[ ! -z "${TOR_CONTROL_PORT}" ]]; then
        info "  ControlPort set: ${TOR_CONTROL_PORT}"
        info "  PASSWORD: $PASSWORD"
    fi
    if [[ ! -z "${HTTPS_PROXY}" ]]; then
        info "  HTTPSProxy set: ${HTTPS_PROXY}"
    fi
    if [[ ! -z "${HTTPS_PROXY_CREDS}" ]]; then
        info "  HTTPSProxyAuthenticator set: $(echo ${HTTPS_PROXY_CREDS} | sed 's/:.*$/:*****/')"
    fi
    if [[ ! -z "${EXCLUDE_EXIT_NODES}" ]]; then
        info "  ExcludeExitNodes set: ${EXCLUDE_EXIT_NODES}"
    fi
    if [[ ! -z "${HTTP_TUNNEL_PORT}" ]]; then
        info "  HTTPTunnelPort set: 0.0.0.0:${HTTP_TUNNEL_PORT}"
    fi
    warn "scanner config:"
    info "  min relays to find set: ${MIN_RELAYS}"
    info "  timeout relay check set: ${RELAY_TIMEOUT}"
    info "  check simultaneously bridges availability set: ${NUM_RELAYS}"
    warn "------------------------------------------------------------------------------"
    echo ""
    info "config examples: https://wiki.archlinux.org/title/tor
    "
    info "tor manual: https://2019.www.torproject.org/docs/tor-manual.html.en
    "
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
#    sed -in 's/$/ IPv4Only' "${BRIDGE_FILE}"
    ## remove lock file
    rm -f "${LOCK_FILE}"
    ## print min relays founded info
    success "number of relays scanner found: $(( $(wc -l < ${BRIDGE_FILE}) - 1 ))"
}

print_debug () {
    ## print all files generated by entrypoint
    if [ ! -z "${DEBUG}" ]; then
        warn "--- ${TOR_CONFIG_FILE}:"
        cat "${TOR_CONFIG_FILE}"
        warn "--- ${BRIDGE_FILE}:"
        cat "${BRIDGE_FILE}"
    fi
}
main () {
    tor_config
    print_config
    map_user
    relay_scan
     ## Display Tor version & torrc in log
    tor --version
    print_config
    print_debug
    ## Execute dockerfile CMD as nonroot alternate gosu                                                                                                                           "
    su-exec "${PUID}:${PGID}" "$@"
}

main "$@"
