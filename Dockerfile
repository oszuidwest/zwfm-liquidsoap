ARG LIQUIDSOAP_VERSION=2.3.3
FROM savonet/liquidsoap:v${LIQUIDSOAP_VERSION}

ARG ODR_AUDIOENC_VERSION=3.6.0
ARG TARGETARCH

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends wget libmagickwand-6.q16-6 \
 && wget -q -O /bin/odr-audioenc "https://github.com/oszuidwest/zwfm-odrbuilds/releases/download/odr-audioenc-v${ODR_AUDIOENC_VERSION}/odr-audioenc-v${ODR_AUDIOENC_VERSION}-minimal-debian-${TARGETARCH}" \
 && chmod +x /bin/odr-audioenc \
 && apt-get remove -y wget \
 && apt-get autoremove -y \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

USER liquidsoap
