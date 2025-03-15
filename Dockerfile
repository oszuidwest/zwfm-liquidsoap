ARG LIQUIDSOAP_VERSION
ARG ODR_AUDIOENC_VERSION
ARG TARGETARCH

FROM savonet/liquidsoap:v${LIQUIDSOAP_VERSION}

USER root

RUN apt-get update && \
    apt-get install -y wget && \
    wget -O /bin/odr-audioenc https://github.com/oszuidwest/zwfm-odrbuilds/releases/download/odr-audioenc-v${ODR_AUDIOENC_VERSION}/odr-audioenc-v${ODR_AUDIOENC_VERSION}-minimal-debian-${TARGETARCH} && \
    chmod +x /bin/odr-audioenc && \
    apt-get remove -y wget && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

USER liquidsoap
