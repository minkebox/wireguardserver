#! /bin/sh

DDNS_DOMAIN=minkebox.net
PRIVATE_HOSTNAME=${__GLOBALID}
DNSSERVER=${__DNSSERVER}
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
DEVICE_INTERFACE=wg0

DEFAULT_CIDR=$(ip addr show dev ${__DEFAULT_INTERFACE} | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}\b" | head -1)
DEFAULT_IP=$(echo ${DEFAULT_CIDR} | sed "s/\/.*$//")

if [ "${SELECTED_SERVER_NETWORK}" != "" ]; then
  SERVER_NETWORK=${SELECTED_SERVER_NETWORK}
else
  SERVER_NETWORK=10.253.122
fi
SERVER_CIDR=${SERVER_NETWORK}.1/24

# Generate keys
if [ ! -e ${PRIVATE_KEY} ]; then
  wg genkey | tee ${PRIVATE_KEY} | wg pubkey > ${PUBLIC_KEY}
  if [ "${SELECTED_PORT}" = "" ]; then
    # Prime random
    RANDOM=$(head -1 /dev/urandom | cksum)
    # Select an unused port at random from within our standard range avoiding any we see as in use
    active_ports=$(upnpc -m ${__NAT_INTERFACE} -L | grep "^ *\d\? UDP\|TCP .*$" | sed "s/^.*:\(\d*\).*$/\1/")
    while true ; do
      PORT=$((${PORTRANGE_START} + RANDOM % ${PORTRANGE_LEN}))
      if ! $(echo $active_ports | grep -q ${PORT}); then
        break;
      fi
    done
  else
    PORT=${SELECTED_PORT}
  fi
  echo ${PORT} > ${PORT_FILE}
fi
PORT=$(cat ${PORT_FILE})

if [ "${INTERNET_ONLY}" = "true" ]; then
  DNSSERVER="1.1.1.1"
fi

# Create server config for clients to read
cat > ${SERVER_CONFIG} <<__EOF__
[Interface]
PrivateKey = ## Client private key on your device ##
Address = ${SERVER_NETWORK}.#ID#/32
DNS = ${DNSSERVER}

[Peer]
PublicKey = $(cat ${PUBLIC_KEY})
Endpoint = ${PRIVATE_HOSTNAME}.${DDNS_DOMAIN}:${PORT}
AllowedIPs = ${SERVER_CIDR}, ${DEFAULT_CIDR}
__EOF__

# Create server config
cat > ${ROOT}/${DEVICE_INTERFACE}.conf <<__EOF__
[Interface]
PrivateKey = $(cat ${PRIVATE_KEY})
Address = ${SERVER_CIDR}
ListenPort = ${PORT}
__EOF__
# Add peers
for client in $(cat ${CLIENTS_CONFIG}); do
  client_id=$(echo ${client} | sed "s/#.*//")
  client_key=$(echo ${client} | sed "s/.*#//")
  cat >> ${ROOT}/${DEVICE_INTERFACE}.conf <<__EOF__
[Peer]
PublicKey = ${client_key}
AllowedIPs = ${SERVER_NETWORK}.${client_id}/32
PersistentKeepalive = 25
__EOF__
done

# Masquarade the vpn
iptables -t nat -I POSTROUTING -o ${__DEFAULT_INTERFACE} -j MASQUERADE

# Internet only
if [ "${INTERNET_ONLY}" = "true" ]; then
  iptables -A FORWARD -i ${DEVICE_INTERFACE} -d 10.0.0.0/8 -j DROP
  iptables -A FORWARD -i ${DEVICE_INTERFACE} -d 172.16.0.0/12 -j DROP
  iptables -A FORWARD -i ${DEVICE_INTERFACE} -d 192.168.0.0/16 -j DROP
fi

# Start Wireguard
wg-quick up ${DEVICE_INTERFACE}

trap "killall sleep; exit" TERM INT

# Open the NAT
sleep 1 &
while wait "$!"; do
  upnpc -m ${__DEFAULT_INTERFACE} -e ${HOSTNAME} -a ${DEFAULT_IP} ${PORT} ${PORT} ${PROTO} ${TTL}
  if [ "${__HOSTIP6}" != "" ]; then
    upnpc -m ${__DEFAULT_INTERFACE} -e ${HOSTNAME}_6 -6 -A "" 0 ${__HOSTIP6} ${PORT} ${PROTO} ${TTL}
  fi
  sleep ${TTL2} &
done
upnpc -m ${__DEFAULT_INTERFACE} -d ${PORT} ${PROTO}
if [ "${__HOSTIP6}" != "" ]; then
  upnpc -m ${__DEFAULT_INTERFACE} -6 -d ${PORT} ${PROTO}
fi
