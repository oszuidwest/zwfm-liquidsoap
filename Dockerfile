ARG LIQUIDSOAP_VERSION=2.4.5
FROM savonet/liquidsoap:v${LIQUIDSOAP_VERSION}

ARG ODR_AUDIOENC_VERSION=next
ARG TARGETARCH

USER root
RUN apt-get update \
 && apt-get upgrade -y --no-install-recommends \
 && apt-get install -y --no-install-recommends iproute2 wget \
 && wget -q -O /usr/local/bin/odr-audioenc "https://github.com/oszuidwest/zwfm-odrbuilds/releases/download/odr-audioenc-${ODR_AUDIOENC_VERSION}/odr-audioenc-${ODR_AUDIOENC_VERSION}-minimal-debian13-${TARGETARCH}" \
 && chmod +x /usr/local/bin/odr-audioenc \
 && apt-get remove -y wget \
 && apt-get autoremove -y \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

COPY --chmod=0755 bin/dab-tcp-ack-monitor /usr/local/bin/dab-tcp-ack-monitor

USER liquidsoap
