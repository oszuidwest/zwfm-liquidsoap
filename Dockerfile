FROM debian:bookworm-slim AS metadata

RUN apt-get update && \
    apt-get install -y libmagickwand-6.q16-6 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
