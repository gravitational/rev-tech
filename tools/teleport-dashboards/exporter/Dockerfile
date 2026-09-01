# Thin runtime image around prebuilt static binaries, one per target arch.
# Build them first with `make binaries`, then `make image` (or buildx directly).
# Compiling here would pull a toolchain into the build and lose the pinned
# Teleport API version that makes the counts trustworthy.
FROM alpine:3.20
RUN apk add --no-cache ca-certificates
WORKDIR /app

# TARGETARCH is set by buildx per platform. Copying a single fixed-arch binary
# is how you get an image that builds cleanly and then dies at runtime with
# "exec format error" on a node of the other architecture -- the build default
# is the HOST arch, not the cluster's.
ARG TARGETARCH
COPY teleport-usage-linux-${TARGETARCH} /app/teleport-usage

# Legacy-name symlinks: argv[0] dispatch selects the matching subcommand, so the
# original teleport-mau-tracker / teleport-tpr-tracker invocations still work.
RUN ln -s /app/teleport-usage /app/teleport-mau-tracker \
 && ln -s /app/teleport-usage /app/teleport-tpr-tracker

# Run as a non-root user. The exporter reads a mounted identity file and serves
# HTTP; it needs no privileges and no writable filesystem.
RUN adduser -D -u 65532 -s /sbin/nologin exporter
USER 65532:65532

EXPOSE 8080

# No default subcommand: the entrypoint is the multiplexer and the caller picks.
# Defaulting to a subcommand here is how the previous image ended up running the
# tracker in places that wanted something else.
ENTRYPOINT ["/app/teleport-usage"]
CMD ["exporter"]
