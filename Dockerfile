ARG LIQUIDSOAP_VERSION
FROM savonet/liquidsoap:v${LIQUIDSOAP_VERSION}

ARG ODR_AUDIOENC_VERSION
ARG ODR_PADENC_VERSION
ARG TARGETARCH

USER root

RUN apt-get update && \
    apt-get install -y wget libmagickwand-6.q16-6 && \
    wget -O /bin/odr-audioenc https://github.com/oszuidwest/zwfm-odrbuilds/releases/download/odr-audioenc-v${ODR_AUDIOENC_VERSION}/odr-audioenc-v${ODR_AUDIOENC_VERSION}-minimal-debian-${TARGETARCH} && \
    wget -O /bin/odr-padenc https://github.com/oszuidwest/zwfm-odrbuilds/releases/download/odr-padenc-v${ODR_PADENC_VERSION}/odr-padenc-v${ODR_PADENC_VERSION}-debian-${TARGETARCH} && \
    chmod +x /bin/odr-audioenc /bin/odr-padenc && \
    apt-get remove -y wget && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

USER liquidsoap
