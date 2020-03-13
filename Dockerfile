FROM alpine:latest

RUN apk --no-cache add wireguard-tools miniupnpc dbus avahi ;\
    rm -f /etc/avahi/services/*

COPY root/ /

VOLUME /etc/wireguard

ENTRYPOINT ["/startup.sh"]
