TELEPORT_VERSION ?= $(shell awk '/github.com\/gravitational\/teleport\/api/ {print $$2}' go.mod)
GOOS   ?= $(shell go env GOOS)
GOARCH ?= $(shell go env GOARCH)
EXE    := $(if $(filter windows,$(GOOS)),.exe,)

GO_BUILD = CGO_ENABLED=0 GOOS=$(GOOS) GOARCH=$(GOARCH) go build -trimpath -ldflags='-s -w'

.PHONY: build mau tpr build-for clean fmt

build: mau tpr

mau:
	$(GO_BUILD) -o teleport-mau-tracker$(EXE) mau.go

tpr:
	$(GO_BUILD) -o teleport-tpr-tracker$(EXE) tpr.go

# Re-pin the Teleport API to a specific version, then build for the host platform.
# Usage: make build-for TELEPORT_VERSION=v18.5.1
build-for:
	go get github.com/gravitational/teleport/api@$(TELEPORT_VERSION)
	go mod tidy
	$(MAKE) build

clean:
	rm -f teleport-mau-tracker teleport-tpr-tracker \
	      teleport-mau-tracker.exe teleport-tpr-tracker.exe

fmt:
	gofmt -w mau.go tpr.go
