// Package teleportclient centralizes construction of the Teleport API client
// shared by the mau and tpr subcommands. When identityFile is non-empty the
// client authenticates with an exported identity file; otherwise it falls back
// to the ambient tsh profile (LoadProfile).
//
// Long-running callers should use Provider rather than Connect: an identity
// file written by tbot is rewritten on tbot's renewal schedule, and a client
// built once from it keeps the original credentials for the life of the
// process.
package teleportclient

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"sync"
	"time"

	"github.com/gravitational/teleport/api/client"
)

// DefaultCheckInterval is the minimum time between two staleness checks of the
// identity file. Client can therefore be called on a hot path without hashing
// the file on every call.
const DefaultCheckInterval = 30 * time.Second

// Connect builds a *client.Client for proxy. If identityFile is non-empty it is
// used for credentials; otherwise the ambient tsh profile is loaded.
//
// The returned client holds the credentials it was built with forever. Use
// Provider if the process outlives an identity renewal.
func Connect(ctx context.Context, proxy, identityFile string) (*client.Client, error) {
	var credentials []client.Credentials
	if identityFile != "" {
		credentials = []client.Credentials{
			client.LoadIdentityFile(identityFile),
		}
	} else {
		credentials = []client.Credentials{
			client.LoadProfile("", ""),
		}
	}

	return client.New(ctx, client.Config{
		Addrs:       []string{proxy},
		Credentials: credentials,
	})
}

// Provider hands out a Teleport API client, rebuilding it when the identity
// file on disk changes. tbot rewrites that file on its own schedule; a client
// constructed once holds the original credentials forever and every call fails
// authentication after the first rotation with
//
//	ssh: handshake failed: ssh: unable to authenticate, attempted methods [none publickey]
//
// Change is detected by hashing the file contents rather than by comparing
// modification times: some writers preserve mtime, and a rewrite that produces
// identical bytes needs no reconnect.
//
// A Provider with an empty identityFile authenticates from the ambient tsh
// profile and never reconnects, since there is no file to watch.
type Provider struct {
	proxy        string
	identityFile string

	mu           sync.Mutex
	clt          *client.Client
	identityHash string
	lastCheck    time.Time

	// checkInterval bounds how often the identity file is hashed.
	checkInterval time.Duration

	// dial, closeClient and now are seams for tests. Production values are set
	// by NewProvider and are never nil.
	dial        func(ctx context.Context, proxy, identityFile string) (*client.Client, error)
	closeClient func(*client.Client) error
	now         func() time.Time
}

// NewProvider does not dial. Call Client to obtain a connected client.
func NewProvider(proxy, identityFile string) *Provider {
	return &Provider{
		proxy:         proxy,
		identityFile:  identityFile,
		checkInterval: DefaultCheckInterval,
		dial:          Connect,
		closeClient:   func(c *client.Client) error { return c.Close() },
		now:           time.Now,
	}
}

// Client returns a connected client, reconnecting first if the identity file
// changed since the last call. Safe for concurrent use.
//
// When a reconnect is needed the previous client is closed before the new one
// is dialed, and a failed dial is reported to the caller. The stale client is
// never handed back: its credentials are precisely the ones that were just
// rotated away, so every call made with it would fail authentication.
func (p *Provider) Client(ctx context.Context) (*client.Client, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.clt != nil && !p.identityChangedLocked() {
		return p.clt, nil
	}

	// Hash before dialing so the recorded hash describes the bytes the new
	// client is built from. An unreadable file here means the dial would fail
	// anyway, so report it without attempting one.
	hash, err := hashFile(p.identityFile)
	if err != nil {
		return nil, fmt.Errorf("reading identity file %s: %w", p.identityFile, err)
	}

	// Release the current client first: its credentials are known stale, and
	// holding it while the dial fails is what would let it leak back out.
	// A close error is not actionable here; the connection is being discarded.
	_ = p.closeCurrentLocked()

	clt, err := p.dial(ctx, p.proxy, p.identityFile)
	if err != nil {
		// clt stays nil, so the next Client call retries the dial immediately
		// instead of waiting out another check interval.
		return nil, fmt.Errorf("connecting to Teleport proxy %s: %w", p.proxy, err)
	}

	p.clt = clt
	p.identityHash = hash
	p.lastCheck = p.now()
	return clt, nil
}

// identityChangedLocked reports whether the identity file differs from the one
// the current client was built with. It hashes the file at most once per
// checkInterval and updates lastCheck when it does. The caller must hold p.mu.
func (p *Provider) identityChangedLocked() bool {
	if p.identityFile == "" {
		// Ambient profile: nothing on disk to watch.
		return false
	}

	now := p.now()
	if now.Sub(p.lastCheck) < p.checkInterval {
		return false
	}

	hash, err := hashFile(p.identityFile)
	if err != nil {
		// tbot writes the identity atomically via rename, so the path can be
		// briefly absent. A working client is worth more than a reaction to a
		// transient read failure. lastCheck is deliberately left alone so the
		// next call retries rather than waiting out another interval.
		return false
	}

	p.lastCheck = now
	return hash != p.identityHash
}

// Close releases the current client, if any. It is safe to call more than once,
// and a Provider may be reused afterwards: the next Client call dials again.
func (p *Provider) Close() error {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.closeCurrentLocked()
}

// closeCurrentLocked closes and clears the current client. The caller must hold
// p.mu.
func (p *Provider) closeCurrentLocked() error {
	if p.clt == nil {
		return nil
	}
	clt := p.clt
	p.clt = nil
	p.identityHash = ""
	return p.closeClient(clt)
}

// hashFile returns the hex-encoded SHA-256 of the file at path. An empty path
// yields an empty hash, which is the ambient-profile case.
func hashFile(path string) (string, error) {
	if path == "" {
		return "", nil
	}
	// Identity files are a few kilobytes; reading the whole thing keeps the
	// hash consistent with a single atomic read of the file.
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:]), nil
}
