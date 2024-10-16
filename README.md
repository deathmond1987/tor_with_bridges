## forked from https://github.com/BarneyBuffet/docker-tor

Tor with tor relay scanner by ValdikSS

Tor options (.env file)

    SOCKS_IP=0.0.0.0 # tor listen address
    SOCKS_PORT=9050 # tor port
    EXIT_RELAY=0 # exit relay. 0 - off, 1- on
      
    HTTPS_PROXY= # use proxy
    HTTPS_PROXY_CREDS= # auth for proxy
    SOCKS_ACCEPT= # accept policy rules
    SOCKS_REJECT= # reject policy rules
    EXCLUDE_EXIT_NODES={ru}, {fr} # exclude exit nodes
    TOR_CONTROL_PORT=9051 # control port
    PASSWORD=TESTTESTTEST # passwd for tor control. if empty - it will be generated
    DEBUG=true # container debug (set -xv)
    HTTP_TUNNEL_PORT= # if we need http proxy
    
    #### tor relay scanner options ####
    NUM_RELAYS=100 # number of simultaneous connections
    MIN_RELAYS=3 # min founded relays before start
    RELAY_TIMEOUT=3 # timeout check relay
    
    #### timezone options ####
    TZ=Europe/Moscow
