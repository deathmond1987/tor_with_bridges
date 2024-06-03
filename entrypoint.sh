#!/usr/bin/env bash
#set -x
set -euo pipefail
## colors
reset="\033[0m"
red="\033[0;31m"
green="\033[0;32m"
white="\033[0;37m"
tan="\033[0;33m"

info() { printf "${white}➜ %s${reset}\n" "$@"
}
success() { printf "${green}✔ %s${reset}\n" "$@"
}
error() { >&2 printf "${red}✖ %s${reset}\n" "$@"
}
warn() { printf "${tan}➜ %s${reset}\n" "$@"
}

TOR_CONFIG_FILE=${DATA_DIR}/torrc
BRIDGE_FILE=${DATA_DIR}/torrc_bridges
LOCK_FILE=${DATA_DIR}/.lock

## default values
SOCKS_IP=${SOCKS_IP:=127.0.0.1}
SOCKS_PORT=${SOCKS_PORT:=9050}
SOCKS_ACCEPT=${SOCKS_ACCEPT:=}
SOCKS_REJECT=${SOCKS_REJECT:=}
EXIT_RELAY=${EXIT_RELAY:=0}
## set tor relay scanner variables
NUM_RELAYS=${NUM_RELAYS:=100}
MIN_RELAYS=${MIN_RELAYS:=1}
RELAY_TIMEOUT=${RELAY_TIMEOUT:=3}

if [[ -f "${TOR_CONFIG_FILE}" ]]; then  
    warn "removing old config"
    rm -f "${TOR_CONFIG_FILE}"
fi


if [[ -f "${BRIDGE_FILE}" ]]; then
    warn "removing old bridge config"
    rm -f "${BRIDGE_FILE}"
fi

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
        ${DATA_DIR}
    warn "Enforced ownership of ${DATA_DIR} to nonroot:nonroot"

    ## Make sure volume permissions are correct
    chmod -R go=rX,u=rwX \
        ${DATA_DIR}
    warn "Enforced permissions for ${DATA_DIR} to go=rX & u=rwX"

    ## Export to the rest of the bash script
    export PUID
    export PGID
}

tor_config () {
    warn "SocksPort value ${SOCKS_IP}:${SOCKS_PORT} saved to ${TOR_CONFIG_FILE}"
    echo "SocksPort $SOCKS_IP:$SOCKS_PORT" >> "${TOR_CONFIG_FILE}"
    if [[ ! -z "${SOCKS_ACCEPT}" ]]; then
        warn "SocksPolicy accept ${SOCKS_ACCEPT} saved to ${TOR_CONFIG_FILE}"
        echo "SocksPolicy accept ${SOCKS_ACCEPT}" >> "${TOR_CONFIG_FILE}"
    fi
    if [[ ! -z "${SOCKS_REJECT}" ]]; then
        warn "SocksPolicy reject ${SOCKS_REJECT} saved to ${TOR_CONFIG_FILE}"
        echo "SocksPolicy reject ${SOCKS_REJECT}" >> "${TOR_CONFIG_FILE}"
    fi
    warn "set exit relay to $EXIT_RELAY"
    echo "ExitRelay $EXIT_RELAY" >> "${TOR_CONFIG_FILE}"
#    echo "UseBridges 1" >> "${TOR_CONFIG_FILE}"
    echo "%include $BRIDGE_FILE" >> "${TOR_CONFIG_FILE}"
    warn "min relays to find set to $MIN_RELAYS"
    warn "number of parallel connections to bridges to check availability set to $NUM_RELAYS"
    warn "timeout relay check set to $RELAY_TIMEOUT"

}

main () {
    echo -e ""
    warn "====================================- INITIALISING TOR -===================================="
    echo -e ""

    tor_config
    map_user

    echo -e ""
    success "====================================- STARTING TOR WITH RELAYS BUNDLE -===================================="
    echo -e ""
 
     ## creating lock file to temporary disable healthcheck
    touch "${LOCK_FILE}"

    ## searching open port from bridge list with tor-relay-scanner by valdikSS
    ## and write founded list to file
    while [ ! -s "$BRIDGE_FILE" ]; do
        tor-relay-scanner --torrc \
                          -n "${NUM_RELAYS}" \
                          -g "${MIN_RELAYS}" \
                          --timeout "${RELAY_TIMEOUT}" > "${BRIDGE_FILE}"
    done
 
    success "number of relays scanner found: $(( $(wc -l < ${BRIDGE_FILE}) - 1 ))"

     ## Display Tor version & torrc in log
    tor --version
    rm -f "${LOCK_FILE}"
    ## Execute dockerfile CMD as nonroot alternate gosu                                                                                                                           "
    su-exec "${PUID}:${PGID}" "$@"
}

main "$@"