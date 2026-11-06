#!/usr/bin/env bash
# Regenerates ./gen/python from Teleport's upstream .proto definitions, at a
# PINNED release tag -- not whatever happens to be on master today.
#
# Teleport doesn't publish Python gRPC bindings, so we compile them ourselves
# from the open-source proto definitions in gravitational/teleport, plus the
# two external deps they reference (gogoproto, google/rpc/status).
#
# Proto definitions change between Teleport releases -- fields get added,
# RPCs get deprecated/renamed, whole services get introduced. Pinning to a
# tag means regenerating is a deliberate, reviewable action (the diff shows
# exactly what changed) instead of a silent moving target. See the
# "Versioning & upgrading" section in README.md before bumping this.
set -euo pipefail

TELEPORT_VERSION="${TELEPORT_VERSION:-v18.10.0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$(mktemp -d)"
trap 'rm -rf "$SRC_DIR"' EXIT

pip install --user --quiet -r "$SCRIPT_DIR/requirements.txt" grpcio-tools

echo "Fetching api/proto from gravitational/teleport @ ${TELEPORT_VERSION} (sparse checkout)..."
git clone --filter=blob:none --no-checkout --depth 1 --branch "$TELEPORT_VERSION" \
  https://github.com/gravitational/teleport.git "$SRC_DIR"
(
  cd "$SRC_DIR"
  git sparse-checkout init --cone
  git sparse-checkout set api/proto api/gen api/types
  git checkout
)

echo "Fetching external proto deps (gogoproto, google/rpc/status)..."
mkdir -p "$SRC_DIR/third_party/gogoproto" "$SRC_DIR/third_party/google/rpc"
curl -sL -o "$SRC_DIR/third_party/gogoproto/gogo.proto" \
  https://raw.githubusercontent.com/gogo/protobuf/master/gogoproto/gogo.proto
curl -sL -o "$SRC_DIR/third_party/google/rpc/status.proto" \
  https://raw.githubusercontent.com/googleapis/googleapis/master/google/rpc/status.proto

echo "Compiling .proto -> Python..."
rm -rf "$SCRIPT_DIR/gen/python"
mkdir -p "$SCRIPT_DIR/gen/python"
find "$SRC_DIR/api/proto" "$SRC_DIR/third_party" -name '*.proto' > "$SRC_DIR/all_protos.txt"
python3 -m grpc_tools.protoc \
  -I "$SRC_DIR/api/proto" -I "$SRC_DIR/third_party" \
  --python_out="$SCRIPT_DIR/gen/python" \
  --grpc_python_out="$SCRIPT_DIR/gen/python" \
  $(cat "$SRC_DIR/all_protos.txt")

echo "$TELEPORT_VERSION" > "$SCRIPT_DIR/gen/TELEPORT_VERSION"
echo "Done. Stubs generated from Teleport ${TELEPORT_VERSION}, written to $SCRIPT_DIR/gen/python"
