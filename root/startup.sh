#! /bin/sh

HOME_INTERFACE=${__HOME_INTERFACE}
DDNS_DOMAIN=minkebox.net
PRIVATE_HOSTNAME=${__GLOBALID}
PROTO=udp
TTL=600 # 10 minutes
TTL2=300 # TTL/2
ROOT=/etc/wireguard
SERVER_CONFIG=${ROOT}/server.info
CLIENTS_CONFIG=${ROOT}/clients.info
PRIVATE_KEY=${ROOT}/key.private
PUBLIC_KEY=${ROOT}/key.public
PORT_FILE=${ROOT}/port
PORTRANGE_START=41310
PORTRANGE_LEN=256
SERVER_NETWORK=10.253.122
SERVER_CIDR=${SERVER_NETWORK}.1/24
DEVICE=wg0

HOME_CIDR=$(ip addr show dev ${HOME_INTERFACE} | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}\b" | head -1)
HOME_IP=$(echo ${HOME_CIDR} | sed "s/\/.*$//")

# Generate keys
if [ ! -e ${PRIVATE_KEY} ]; then
  wg genkey | tee ${PRIVATE_KEY} | wg pubkey > ${PUBLIC_KEY}
  if [ "${SELECTED_PORT}" = "" ]; then
    # Prime random
    RANDOM=$(head -1 /dev/urandom | cksum)
    # Select an unused port at random from within our standard range avoiding any we see as in use
    active_ports=$(upnpc -m ${HOME_INTERFACE} -L | grep "^ *\d\? UDP\|TCP .*$" | sed "s/^.*:\(\d*\).*$/\1/")
    while true ; do
      PORT=$((${PORTRANGE_START} + RANDOM % ${PORTRANGE_LEN}))
      if ! $(echo $active_ports | grep -q ${PORT}); then
        if ! $(echo $active_ports | grep -q ${PORT_TUN}); then
          break;
        fi
      fi
    done
  else
    PORT=${SELECTED_PORT}
  fi
  echo ${PORT} > ${PORT_FILE}
fi
PORT=$(cat ${PORT_FILE})

# Create server config for clients to read
cat > ${SERVER_CONFIG} <<__EOF__
[Peer]
PublicKey = $(cat ${PUBLIC_KEY})
Endpoint = ${PRIVATE_HOSTNAME}.${DDNS_DOMAIN}:${PORT}
AllowedIPs = ${SERVER_CIDR}, ${HOME_CIDR}
__EOF__

# Create server config
cat > ${ROOT}/${DEVICE}.conf <<__EOF__
[Interface]
PrivateKey = $(cat ${PRIVATE_KEY})
Address = ${SERVER_CIDR}
ListenPort = ${PORT}
PersistentKeepalive = 25
__EOF__
# Add peers
nr=2
for client_key in $(cat ${CLIENTS_CONFIG}); do
  cat >> ${ROOT}/${DEVICE}.conf <<__EOF__
[Peer]
PublicKey = ${client_key}
AllowedIPs = ${SERVER_NETWORK}.${nr}/32
__EOF__
  nr=$((${nr} + 1))
done

# Masquarade the vpn
iptables -t nat -I POSTROUTING -o ${HOME_INTERFACE} -j MASQUERADE

# Start Wireguard
wg-quick up ${DEVICE}

# Open the NAT
sleep 1 &
while wait "$!"; do
  upnpc -e ${HOSTNAME}_wg -a ${HOME_IP} ${PORT} ${PORT} ${PROTO} ${TTL}
  if [ "${__HOSTIP6}" != "" ]; then
    upnpc -e ${HOSTNAME}_wg6 -6 -A "" 0 ${__HOSTIP6} ${PORT} ${PROTO} ${TTL}
  fi
  sleep ${TTL2} &
done
upnpc -d ${PORT} ${PROTO}
