# Optional: a real pre-built image, for pushing to your own registry
# instead of the default self-compiling-in-ubuntu approach chart/templates/job.yaml
# uses (see chart/values.yaml's `selfCompile`). Build from this
# directory: `docker build -t <tag> .`
FROM golang:1.25 AS build
WORKDIR /src
COPY chart/app/go.mod chart/app/go.sum ./
RUN go mod download
COPY chart/app/main.go ./
RUN CGO_ENABLED=0 go build -o /transact .

FROM gcr.io/distroless/static-debian12
COPY --from=build /transact /transact
USER 65534:65534
ENTRYPOINT ["/transact"]
