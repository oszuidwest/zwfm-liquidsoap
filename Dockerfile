ARG LIQUIDSOAP_VERSION
ARG ODR_AUDIOENC_VERSION
ARG TARGETARCH

FROM savonet/liquidsoap:v${LIQUIDSOAP_VERSION}

RUN echo "Liquidsoap version: ${LIQUIDSOAP_VERSION}"
RUN echo "ODR-AudioEnc version: ${ODR_AUDIOENC_VERSION}"
RUN echo "Target architecture: ${TARGETARCH}"

USER root

RUN apt-get update && \
    apt-get install -y wget && \
    wget -O /bin/odr-audioenc https://github.com/oszuidwest/zwfm-odrbuilds/releases/download/${ODR_AUDIOENC_VERSION}/${ODR_AUDIOENC_VERSION}-minimal-debian-${TARGETARCH} && \
    chmod +x /bin/odr-audioenc && \
    apt-get remove -y wget && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

USER liquidsoap
