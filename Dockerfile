## Pinned version tag from https://hub.docker.com/_/alpine
ARG ALPINE_VER=latest

########################################################################################
## STAGE ZERO - BUILD TOR RELAY SCANNER
########################################################################################

FROM alpine:$ALPINE_VER AS bridge-builder

## Set app dir
ARG APP_DIR=torparse
## Get build packages
RUN apk add python3 \
    py3-pip \
## pep-668
    pipx \
    git \
    binutils &&\
## Get pyinstaller
    pipx install pyinstaller &&\
## Add pipx to PATH
    export PATH=/root/.local/bin:$PATH &&\
## Get source
    git clone --branch main https://github.com/ValdikSS/tor-relay-scanner.git &&\
## Move to source dir
    cd tor-relay-scanner &&\
## Install package to $APP_DIR
    pip install . --target "$APP_DIR" &&\
## Remove cache from dir
    find "$APP_DIR" -path '*/__pycache__*' -delete &&\
## copy main to app dir
    cp "$APP_DIR"/tor_relay_scanner/__main__.py "$APP_DIR"/ &&\
## build elf from app dir
    pyinstaller -F --paths "$APP_DIR" "$APP_DIR"/__main__.py


########################################################################################
## STAGE ONE - BUILD TOR
########################################################################################
FROM alpine:$ALPINE_VER AS tor-builder

## TOR_VER can be overwritten with --build-arg at build time
## Get latest version from > https://dist.torproject.org/
ARG TOR_VER=0.4.8.11
ARG TORGZ=https://dist.torproject.org/tor-$TOR_VER.tar.gz
#ARG TOR_KEY=0x6AFEE6D49E92B601

## Install tor make requirements
RUN apk --no-cache add --update \
    alpine-sdk \
    gnupg \
    libevent libevent-dev \
    zlib zlib-dev \
    openssl openssl-dev git
## Get Tor key file and tar source file
RUN wget $TORGZ

## Make install Tor
RUN tar xfz tor-$TOR_VER.tar.gz &&\
    cd tor-$TOR_VER &&\
    ./configure &&\
    make -j 8 install

########################################################################################
## STAGE TWO - RUNNING IMAGE
########################################################################################
FROM alpine:$ALPINE_VER as release

## CREATE NON-ROOT USER FOR SECURITY
RUN addgroup --gid 1001 --system nonroot && \
    adduser  --uid 1000 --system --ingroup nonroot --home /home/nonroot nonroot

## Install Alpine packages
## bind-tools is needed for DNS resolution to work in *some* Docker networks
## Tini allows us to avoid several Docker edge cases, see https://github.com/krallin/tini.
RUN apk --no-cache add \
    bash \
    curl \
    libevent \
    tini su-exec \
    openssl \
    tzdata \
    xz-dev
## data directory
ENV DATA_DIR=/tor

## Create tor directories
RUN mkdir -p ${DATA_DIR} && chown -R nonroot:nonroot ${DATA_DIR} && chmod -R go+rX,u+rwX ${DATA_DIR}

COPY --from=bridge-builder --chmod=777 /tor-relay-scanner/dist/__main__ /usr/local/sbin/tor-relay-scanner
## Copy compiled Tor daemon from tor-builder
COPY --from=tor-builder /usr/local/ /usr/local/

## Copy entrypoint shell script for templating torrc
COPY --chown=nonroot:nonroot --chmod=700 entrypoint.sh /usr/local/bin

## Docker health check
## also restart logic. if curl cannot fetch info - we kill tor process to force restart container by restart: always directive in docker-compose.yml
HEALTHCHECK --interval=5m --retries=2 \
            CMD if [ -f ${DATA_DIR}/.lock ]; then echo "tor starting...";  else curl --retry 4 --max-time 10 -xs --socks5-hostname 127.0.0.1:${SOCKS_PORT} 'https://check.torproject.org' | tac | grep -qm1 Congratulations || pkill tor; fi


## ENV VARIABLES
## Default values
ENV PUID= \
    PGID= 

## Label the docker image
LABEL maintainer="Sidorin Konstantin <Deathmond1987@gmail.com>"
LABEL name="Tor network client (daemon) with custom bridges"
LABEL version=$TOR_VER
LABEL description="A docker image for tor with bridge finder"
LABEL license="GNU"
LABEL url="https://www.torproject.org"
LABEL vcs-url="https://github.com/deathmond1987/tor_with_bridges/"

WORKDIR ${DATA_DIR}
ENTRYPOINT ["/sbin/tini", "--", "entrypoint.sh"]
CMD ["tor", "-f", "/tor/torrc"]
