FROM alpine:latest

RUN apk --no-cache add wireguard-tools miniupnpc ;\

COPY root/ /

VOLUME /etc/wireguard

ENTRYPOINT ["/startup.sh"]
