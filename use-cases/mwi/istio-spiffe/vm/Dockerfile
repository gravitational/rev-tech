# Stage 1: pull the Envoy binary from the official image
FROM envoyproxy/envoy:v1.29-latest AS envoy-base

# Stage 2: runtime image
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    curl \
    gettext-base \
    && rm -rf /var/lib/apt/lists/*

# Copy Envoy binary from official image (supports both amd64 and arm64)
COPY --from=envoy-base /usr/local/bin/envoy /usr/local/bin/envoy

# Install tbot — version must match your Teleport cluster
ARG TELEPORT_VERSION=18.7.6
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fsSL "https://cdn.teleport.dev/teleport-v${TELEPORT_VERSION}-linux-${ARCH}-bin.tar.gz" \
       -o /tmp/tele.tar.gz \
    && tar xzf /tmp/tele.tar.gz -C /tmp \
    && install -m 755 /tmp/teleport/tbot /usr/local/bin/tbot \
    && rm -rf /tmp/teleport /tmp/tele.tar.gz

COPY tbot-vm.yaml /etc/tbot/tbot.yaml.tmpl
COPY envoy.yaml   /etc/envoy/envoy.yaml.tmpl
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
