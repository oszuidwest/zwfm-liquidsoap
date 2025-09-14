ARG LIQUIDSOAP_VERSION=2.4.0
FROM savonet/liquidsoap:v${LIQUIDSOAP_VERSION}

ARG ODR_AUDIOENC_VERSION=next
ARG TARGETARCH

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends wget libmagickwand-6.q16-6 \
 && wget -q -O /bin/odr-audioenc "https://github.com/oszuidwest/zwfm-odrbuilds/releases/download/odr-audioenc-${ODR_AUDIOENC_VERSION}/odr-audioenc-${ODR_AUDIOENC_VERSION}-minimal-debian12-${TARGETARCH}" \
 && chmod +x /bin/odr-audioenc \
 && apt-get remove -y wget \
 && apt-get autoremove -y \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

USER liquidsoap
