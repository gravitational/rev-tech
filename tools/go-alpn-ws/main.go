package main

import (
	"bufio"
	"context"
	"crypto/tls"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/coder/websocket"
)

const wsSubproto = "alpn" // Teleport expects this for the /webapi/connectionupgrade ALPN routing mode.

func main() {
	proxy := flag.String("proxy", "", "proxy host:port to target (e.g. teleport.example.com:443)")
	alpn := flag.String("alpn", "", "ALPN listener to request inside the websocket (e.g. teleport-reversetunnel)")
	insecure := flag.Bool("insecure", false, "skip TLS verification (applies to both outer and inner TLS; debug only)")
	timeout := flag.Duration("timeout", 20*time.Second, "overall timeout")
	path := flag.String("path", "/webapi/connectionupgrade", "websocket upgrade path")
	flag.Parse()

	if *proxy == "" || *alpn == "" {
		fmt.Fprintln(os.Stderr, "usage: -proxy host:port -alpn protocol [-insecure]")
		flag.PrintDefaults()
		os.Exit(2)
	}

	host, port, err := net.SplitHostPort(*proxy)
	if err != nil {
		fmt.Fprintf(os.Stderr, "invalid -proxy %q: %v\n", *proxy, err)
		os.Exit(2)
	}
	if port == "" {
		port = "443"
	}

	wsURL := fmt.Sprintf("wss://%s%s", net.JoinHostPort(host, port), *path)
	fmt.Printf("==> WS upgrade: %s\n", wsURL)

	ctx, cancel := context.WithTimeout(context.Background(), *timeout)
	defer cancel()

	// Outer TLS config: for the wss:// websocket upgrade.
	outerTLS := &tls.Config{
		ServerName:         host,
		InsecureSkipVerify: *insecure,
		MinVersion:         tls.VersionTLS12,
	}

	httpClient := &http.Client{
		Timeout: *timeout,
		Transport: &http.Transport{
			Proxy:               http.ProxyFromEnvironment,
			TLSClientConfig:     outerTLS,
			ForceAttemptHTTP2:   true,
			IdleConnTimeout:     30 * time.Second,
			TLSHandshakeTimeout: 10 * time.Second,
		},
	}

	ws, resp, err := websocket.Dial(ctx, wsURL, &websocket.DialOptions{
		HTTPClient:   httpClient,
		Subprotocols: []string{wsSubproto}, // sets Sec-WebSocket-Protocol
	})
	if err != nil {
		if resp != nil {
			fmt.Fprintf(os.Stderr, "websocket dial failed: %v (HTTP %s)\n", err, resp.Status)
		} else {
			fmt.Fprintf(os.Stderr, "websocket dial failed: %v\n", err)
		}
		os.Exit(1)
	}
	defer ws.Close(websocket.StatusNormalClosure, "done")

	fmt.Printf("    HTTP status: %s\n", resp.Status)
	fmt.Printf("    Sec-WebSocket-Protocol (server): %q\n", resp.Header.Get("Sec-WebSocket-Protocol"))

	// Treat websocket as a stream net.Conn (binary frames).
	stream := websocket.NetConn(context.Background(), ws, websocket.MessageBinary)

	fmt.Printf("==> Inner TLS handshake with ALPN=%q\n", *alpn)

	// Inner TLS config: this is the important one for ALPN routing.
	innerCfg := &tls.Config{
		ServerName:         host,
		NextProtos:         []string{*alpn},
		MinVersion:         tls.VersionTLS12,
		InsecureSkipVerify: true, // always insecure, as Teleport's host certs are not standards compliant
	}

	tlsConn := tls.Client(stream, innerCfg)
	if err := tlsConn.Handshake(); err != nil {
		fmt.Fprintf(os.Stderr, "inner TLS handshake failed: %v\n", err)
		os.Exit(1)
	}
	defer tlsConn.Close()

	cs := tlsConn.ConnectionState()
	fmt.Printf("    negotiated ALPN: %q\n", cs.NegotiatedProtocol)

	// If we successfully hit teleport-reversetunnel, the server will speak SSH first.
	// Read the first line/banner. Typical is: "SSH-2.0-Teleport\r\n"
	err = tlsConn.SetReadDeadline(time.Now().Add(5 * time.Second))
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to set read deadline: %v\n", err)
		os.Exit(1)
	}
	r := bufio.NewReader(tlsConn)
	line, err := r.ReadString('\n')
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to read banner: %v\n", err)
		os.Exit(1)
	}

	// Print banner exactly as received (trim just for display clarity).
	fmt.Printf("==> Banner: %s", line)
	if !strings.HasSuffix(line, "\n") {
		fmt.Println()
	}
}
