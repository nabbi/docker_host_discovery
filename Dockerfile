FROM alpine:3.21

RUN apk add --no-cache \
    nmap \
    zmap \
    fping \
    masscan \
    arp-scan \
    nbtscan \
    libpcap-dev \
    bash \
    iproute2-minimal

COPY bin/ /usr/local/bin/

CMD ["/bin/bash"]
