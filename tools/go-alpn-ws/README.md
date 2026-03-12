# go-alpn-ws

A small command-line tool for testing Teleport ALPN routing over WebSockets, useful when Teleport is deployed behind a Layer 7 load balancer that terminates TLS.

This replicates the same behaviour Teleport agents use when they cannot rely on direct ALPN routing on the outer TLS connection.

[Docs here](https://goteleport.com/docs/reference/architecture/tls-routing/#working-with-layer-7-load-balancers-or-reverse-proxies) on how this works.

## Background

Normally, Teleport reverse tunnel connections can be tested with:

```bash
openssl s_client -connect proxy.example.com:443 -alpn teleport-reversetunnel
```

However, when Teleport is deployed behind a layer 7 load balancer, the connection flow changes:

1. Client performs a WebSocket upgrade to the Teleport proxy:
   ```
   wss://<proxy>/webapi/connectionupgrade
   ```
2. The WebSocket uses the `Sec-WebSocket-Protocol: alpn` subprotocol.
3. Inside the WebSocket stream, the client performs a second TLS handshake.
4. That inner TLS handshake requests the target Teleport listener via ALPN (`teleport-reversetunnel`, `teleport-proxy-ssh`, etc)

(you can find a rough list of nextProtos available [here](https://github.com/gravitational/teleport/blob/8a81fcb05fbbceb0bad44149e67eb29b3c59311f/lib/service/service_test.go#L834-L869))

This makes `openssl s_client` unusable for debugging, since it cannot perform a WebSocket upgrade and then run TLS inside the upgraded
connection - this tool fills that gap.

## What this tool does

At a high level:

1. Connects to the Teleport proxy using WSS
2. Performs a WebSocket upgrade to `/webapi/connectionupgrade`
3. Negotiates the `alpn` WebSocket subprotocol
4. Treats the WebSocket as a raw `net.Conn`
5. Runs a TLS client handshake inside the WebSocket
6. Requests a specific Teleport listener using ALPN
7. Reads and prints the server banner

For `teleport-reversetunnel` and `teleport-proxy-ssh`, if routing is successful, Teleport replies with an SSH handshake:

```
SSH-2.0-Teleport
```

## Installation

Requires Go 1.20+ (anything reasonably recent should work).

```bash
git clone https://github.com/gravitational/rev-tech
cd go-alpn-ws
go mod tidy
```

Dependencies:
- `github.com/coder/websocket`

## Usage

```bash
go run main.go -proxy teleport.example.com:443 -alpn teleport-reversetunnel
```

### Common ALPN targets

| Listener | ALPN value |
|--------|-----------|
| Reverse tunnel | `teleport-reversetunnel` |
| Proxy SSH | `teleport-proxy-ssh` |
| Proxy MySQL | `teleport-mysql` |
| Proxy Postgres | `teleport-postgres` |

## Example

```bash
$ go run main.go -proxy teleport.example.com:443 -alpn teleport-reversetunnel

==> WS upgrade: wss://teleport.example.com:443/webapi/connectionupgrade
    HTTP status: 101 Switching Protocols
    Sec-WebSocket-Protocol (server): "alpn"
==> Inner TLS handshake with ALPN="teleport-reversetunnel"
    negotiated ALPN: "teleport-reversetunnel"
==> Banner: SSH-2.0-Teleport
```

The `SSH-2.0-Teleport` banner confirms that:
- the WebSocket upgrade succeeded
- ALPN routing inside the WebSocket worked
- the request reached the intended Teleport listener

If the listener doesn't respond or you use an incorrect ALPN protocol, you'll see an error like:

```
inner TLS handshake failed: failed to get reader: failed to read frame header: EOF
exit status 1
```

## TLS verification behavior

Teleport proxy certificates used for ALPN routing are not standards-compliant for normal hostname verification.
Because of this, the tool always disables certificate verification for the inner TLS handshake.

The outer `wss://` connection is normally verified, but verification can also be optionally disabled using:

```bash
-insecure
```

This tool is intended only for debugging and diagnostics.

## Flags

| Flag | Description |
|----|------------|
| `-proxy` | Teleport proxy `host:port` |
| `-alpn` | ALPN listener to request inside the WebSocket |
| `-path` | WebSocket upgrade path (default: `/webapi/connectionupgrade`) |
| `-timeout` | Overall timeout (default: `20s`) |
| `-insecure` | Skip TLS verification for the outer WSS connection |

## Why this exists

This tool is meant to answer one question quickly and reliably:

> *“Is my Teleport proxy correctly routing ALPN traffic when deployed behind an L7 load balancer?”*

If you see `SSH-2.0-Teleport` when requesting the `teleport-reversetunnel` listener, the answer is **yes**.
