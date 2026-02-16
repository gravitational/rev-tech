# Container with uvx based on debian trixie
FROM ghcr.io/astral-sh/uv:trixie-slim

# install common ca certificates for connecting to my teleport cluster later
RUN apt-get update && apt-get install -y ca-certificates curl
RUN update-ca-certificates 

# Create teleport directory, grab v18.2.4 of teleport, extract and install it, and clean up
RUN mkdir /teleport
WORKDIR /teleport
RUN curl -O https://cdn.teleport.dev/teleport-ent-v18.2.4-linux-amd64-bin.tar.gz
RUN tar -xvf teleport-ent-v18.2.4-linux-amd64-bin.tar.gz
RUN ./teleport-ent/install
RUN rm -rf teleport-ent teleport-ent-v18.2.4-linux-amd64-bin.tar.gz

# Run teleport as the entrypoint, using teleport.yaml from our configmap. teleport.yaml contains the MCP commands
ENTRYPOINT ["teleport", "start", "--config", "/teleport/teleport.yaml"]
