FROM savonet/liquidsoap:v${LIQUIDSOAP_VERSION}

USER root

RUN apt-get update && \
    apt-get install -y wget && \
    wget -O /bin/odr-audioenc https://github.com/oszuidwest/zwfm-odrbuilds/releases/download/odr-audioenc-v3.6.0/odr-audioenc-v3.6.0-minimal-debian-${TARGETARCH} && \
    chmod +x /bin/odr-audioenc && \
    apt-get remove -y wget && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

USER liquidsoap
