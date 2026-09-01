TELEPORT_VERSION ?= $(shell awk '/github.com\/gravitational\/teleport\/api/ {print $$2}' go.mod)
GOOS   ?= $(shell go env GOOS)
GOARCH ?= $(shell go env GOARCH)
EXE    := $(if $(filter windows,$(GOOS)),.exe,)

BIN    := teleport-usage
PKG    := ./cmd/teleport-usage

GO_BUILD = CGO_ENABLED=0 GOOS=$(GOOS) GOARCH=$(GOARCH) go build -trimpath -ldflags='-s -w'

.PHONY: build links build-for linux-amd64 test vet clean fmt

# Build the single binary for the host platform.
build:
	$(GO_BUILD) -o $(BIN)$(EXE) $(PKG)

# Build + create the legacy-name symlinks that the argv[0] dispatch recognises.
links: build
	ln -sf $(BIN)$(EXE) teleport-mau-tracker$(EXE)
	ln -sf $(BIN)$(EXE) teleport-tpr-tracker$(EXE)

# Static linux/amd64 build for the cluster nodes.
linux-amd64:
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags='-s -w' -o $(BIN)-linux-amd64 $(PKG)

# Re-pin the Teleport API to a specific version, then build for the host platform.
# Accepts the version with or without a leading "v" (e.g. v18.5.1 or 18.5.1).
# Requires `git` on PATH (only for `ls-remote` — no clone is performed).
# We resolve the tag to a commit SHA and use that as the module version because
# Teleport's api module is published at github.com/gravitational/teleport/api/v18
# for v18+ tags, but we want to keep importing the unsuffixed path. The Go
# module resolver accepts any commit on the unsuffixed path as a pseudo-version.
# Usage: make build-for TELEPORT_VERSION=v18.5.1
build-for:
	@command -v git >/dev/null || { echo "make build-for requires git on PATH"; exit 1; }
	@version=v$(TELEPORT_VERSION:v%=%); \
	sha=$$(git ls-remote https://github.com/gravitational/teleport "refs/tags/$$version" | awk '{print $$1}'); \
	if [ -z "$$sha" ]; then echo "Could not find Teleport tag $$version on github.com/gravitational/teleport"; exit 1; fi; \
	echo "Pinning github.com/gravitational/teleport/api to $$version ($$sha)"; \
	go get github.com/gravitational/teleport/api@$$sha
	go mod tidy
	$(MAKE) build

test:
	go test ./...

vet:
	go vet ./...

clean:
	rm -f $(BIN) $(BIN).exe $(BIN)-linux-amd64 \
	      teleport-mau-tracker teleport-tpr-tracker \
	      teleport-mau-tracker.exe teleport-tpr-tracker.exe

fmt:
	gofmt -w ./cmd ./internal
