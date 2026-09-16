package teleportclient

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/gravitational/teleport/api/client"
)

// fakeDialer stands in for the real Connect. It never touches the network: it
// hands back distinct sentinel *client.Client pointers so tests can tell one
// "connection" from another, and records how many times it was called and what
// it saw on each call.
type fakeDialer struct {
	mu      sync.Mutex
	calls   int
	proxies []string
	files   []string
	// contents records the bytes on disk at the moment of each dial, which is
	// how a test proves the provider re-read a rotated identity file.
	contents []string
	// err, when non-nil for a given call index, is returned instead of a client.
	errs map[int]error

	clients []*client.Client
}

func newFakeDialer() *fakeDialer {
	return &fakeDialer{errs: map[int]error{}}
}

// failOnCall makes the nth dial (1-based) return err.
func (f *fakeDialer) failOnCall(n int, err error) {
	f.errs[n] = err
}

func (f *fakeDialer) dial(_ context.Context, proxy, identityFile string) (*client.Client, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	f.proxies = append(f.proxies, proxy)
	f.files = append(f.files, identityFile)
	if identityFile != "" {
		b, err := os.ReadFile(identityFile)
		if err == nil {
			f.contents = append(f.contents, string(b))
		} else {
			f.contents = append(f.contents, "")
		}
	} else {
		f.contents = append(f.contents, "")
	}
	if err, ok := f.errs[f.calls]; ok && err != nil {
		return nil, err
	}
	// A fresh, distinct pointer per call: identity comparison in the tests is
	// what distinguishes "reused the old client" from "reconnected".
	clt := &client.Client{}
	f.clients = append(f.clients, clt)
	return clt, nil
}

func (f *fakeDialer) count() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.calls
}

// fakeCloser counts Close calls. The real (*client.Client).Close cannot be
// called on the zero-value sentinels the fake dialer produces, so the provider's
// close hook is swapped out too.
type fakeCloser struct {
	mu     sync.Mutex
	closed []*client.Client
	err    error
}

func (f *fakeCloser) close(c *client.Client) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.closed = append(f.closed, c)
	return f.err
}

func (f *fakeCloser) count() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.closed)
}

// testClock is a manually advanced clock so no test ever sleeps.
type testClock struct {
	mu sync.Mutex
	t  time.Time
}

func newTestClock() *testClock {
	return &testClock{t: time.Date(2026, time.September, 1, 12, 0, 0, 0, time.UTC)}
}

func (c *testClock) now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.t
}

func (c *testClock) advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.t = c.t.Add(d)
}

// writeIdentity writes contents to path, failing the test on error.
func writeIdentity(t *testing.T, path, contents string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(contents), 0o600); err != nil {
		t.Fatalf("writing identity file: %v", err)
	}
}

// newTestProvider builds a Provider wired to fakes for dialing, closing and time.
func newTestProvider(t *testing.T, identityFile string) (*Provider, *fakeDialer, *fakeCloser, *testClock) {
	t.Helper()
	dialer := newFakeDialer()
	closer := &fakeCloser{}
	clock := newTestClock()

	p := NewProvider("proxy.example.com:443", identityFile)
	p.dial = dialer.dial
	p.closeClient = closer.close
	p.now = clock.now
	return p, dialer, closer, clock
}

func TestReconnectsWhenIdentityFileChanges(t *testing.T) {
	path := filepath.Join(t.TempDir(), "identity")
	writeIdentity(t, path, "identity-v1")

	p, dialer, closer, clock := newTestProvider(t, path)
	ctx := context.Background()

	first, err := p.Client(ctx)
	if err != nil {
		t.Fatalf("first Client() returned error: %v", err)
	}
	if got := dialer.count(); got != 1 {
		t.Fatalf("dial called %d times after first Client(), want 1", got)
	}

	// tbot rewrites the identity with fresh certificates.
	writeIdentity(t, path, "identity-v2-rotated")
	clock.advance(DefaultCheckInterval + time.Second)

	second, err := p.Client(ctx)
	if err != nil {
		t.Fatalf("second Client() returned error: %v", err)
	}
	if got := dialer.count(); got != 2 {
		t.Fatalf("dial called %d times after rotation, want 2", got)
	}
	if first == second {
		t.Error("Client() returned the same client after the identity file was rotated; the stale credentials would fail every API call")
	}
	if got := closer.count(); got != 1 {
		t.Errorf("old client closed %d times, want 1", got)
	}
	if len(closer.closed) == 1 && closer.closed[0] != first {
		t.Error("the client that was closed is not the original client")
	}
	if dialer.contents[1] != "identity-v2-rotated" {
		t.Errorf("reconnect read identity contents %q, want the rotated contents", dialer.contents[1])
	}
}

func TestDoesNotReconnectWhenContentUnchanged(t *testing.T) {
	path := filepath.Join(t.TempDir(), "identity")
	writeIdentity(t, path, "identity-v1")

	p, dialer, closer, clock := newTestProvider(t, path)
	ctx := context.Background()

	first, err := p.Client(ctx)
	if err != nil {
		t.Fatalf("first Client() returned error: %v", err)
	}

	// Rewrite byte-for-byte identical contents. mtime moves, content does not,
	// so there is nothing to reconnect for.
	clock.advance(DefaultCheckInterval + time.Second)
	writeIdentity(t, path, "identity-v1")

	second, err := p.Client(ctx)
	if err != nil {
		t.Fatalf("second Client() returned error: %v", err)
	}
	if got := dialer.count(); got != 1 {
		t.Errorf("dial called %d times, want 1: identical content must not trigger a reconnect", got)
	}
	if first != second {
		t.Error("Client() returned a new client even though the identity content was unchanged")
	}
	if got := closer.count(); got != 0 {
		t.Errorf("client closed %d times, want 0", got)
	}
}

func TestDoesNotReconnectWithinCheckInterval(t *testing.T) {
	path := filepath.Join(t.TempDir(), "identity")
	writeIdentity(t, path, "identity-v1")

	p, dialer, _, clock := newTestProvider(t, path)
	ctx := context.Background()

	if _, err := p.Client(ctx); err != nil {
		t.Fatalf("first Client() returned error: %v", err)
	}

	writeIdentity(t, path, "identity-v2-rotated")

	// Well inside the check interval: the file is not even hashed.
	clock.advance(DefaultCheckInterval - time.Second)
	for i := 0; i < 5; i++ {
		if _, err := p.Client(ctx); err != nil {
			t.Fatalf("Client() returned error: %v", err)
		}
	}
	if got := dialer.count(); got != 1 {
		t.Errorf("dial called %d times within the check interval, want 1", got)
	}

	// Past the interval, the change is picked up.
	clock.advance(2 * time.Second)
	if _, err := p.Client(ctx); err != nil {
		t.Fatalf("Client() returned error: %v", err)
	}
	if got := dialer.count(); got != 2 {
		t.Errorf("dial called %d times after the interval elapsed, want 2", got)
	}
}

func TestReturnsErrorRatherThanStaleClientOnReconnectFailure(t *testing.T) {
	path := filepath.Join(t.TempDir(), "identity")
	writeIdentity(t, path, "identity-v1")

	p, dialer, closer, clock := newTestProvider(t, path)
	ctx := context.Background()

	dialErr := errors.New("dial tcp: connection refused")
	dialer.failOnCall(2, dialErr)

	first, err := p.Client(ctx)
	if err != nil {
		t.Fatalf("first Client() returned error: %v", err)
	}

	writeIdentity(t, path, "identity-v2-rotated")
	clock.advance(DefaultCheckInterval + time.Second)

	second, err := p.Client(ctx)
	if err == nil {
		t.Fatal("Client() returned nil error after the reconnect failed; callers would keep using credentials that no longer authenticate")
	}
	if !errors.Is(err, dialErr) {
		t.Errorf("Client() error = %v, want it to wrap %v", err, dialErr)
	}
	if second != nil {
		t.Error("Client() returned a non-nil client alongside the reconnect error")
	}
	if second == first {
		t.Error("Client() fell back to the stale client after the reconnect failed")
	}
	if got := closer.count(); got != 1 {
		t.Errorf("stale client closed %d times, want 1: it must be released even when the reconnect fails", got)
	}

	// A failed reconnect leaves no client, so the next call retries immediately
	// rather than waiting out another check interval.
	third, err := p.Client(ctx)
	if err != nil {
		t.Fatalf("third Client() returned error: %v", err)
	}
	if got := dialer.count(); got != 3 {
		t.Errorf("dial called %d times, want 3: the provider must retry after a failed reconnect", got)
	}
	if third == nil || third == first {
		t.Error("third Client() did not return a freshly dialed client")
	}
}

func TestClientReusesConnection(t *testing.T) {
	path := filepath.Join(t.TempDir(), "identity")
	writeIdentity(t, path, "identity-v1")

	p, dialer, _, _ := newTestProvider(t, path)
	ctx := context.Background()

	first, err := p.Client(ctx)
	if err != nil {
		t.Fatalf("Client() returned error: %v", err)
	}
	for i := 0; i < 10; i++ {
		got, err := p.Client(ctx)
		if err != nil {
			t.Fatalf("Client() returned error: %v", err)
		}
		if got != first {
			t.Fatal("Client() returned a different client without any identity change")
		}
	}
	if got := dialer.count(); got != 1 {
		t.Errorf("dial called %d times, want 1", got)
	}
}

func TestFirstDialErrorIsReturned(t *testing.T) {
	path := filepath.Join(t.TempDir(), "identity")
	writeIdentity(t, path, "identity-v1")

	p, dialer, _, _ := newTestProvider(t, path)
	dialErr := errors.New("proxy unreachable")
	dialer.failOnCall(1, dialErr)

	clt, err := p.Client(context.Background())
	if err == nil {
		t.Fatal("Client() returned nil error when the first dial failed")
	}
	if !errors.Is(err, dialErr) {
		t.Errorf("Client() error = %v, want it to wrap %v", err, dialErr)
	}
	if clt != nil {
		t.Error("Client() returned a non-nil client alongside an error")
	}
}

func TestMissingIdentityFileIsAnError(t *testing.T) {
	path := filepath.Join(t.TempDir(), "does-not-exist")

	p, dialer, _, _ := newTestProvider(t, path)

	if _, err := p.Client(context.Background()); err == nil {
		t.Fatal("Client() returned nil error for a missing identity file")
	}
	if got := dialer.count(); got != 0 {
		t.Errorf("dial called %d times with an unreadable identity file, want 0", got)
	}
}

func TestUnreadableIdentityFileKeepsWorkingClient(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "identity")
	writeIdentity(t, path, "identity-v1")

	p, dialer, closer, clock := newTestProvider(t, path)
	ctx := context.Background()

	first, err := p.Client(ctx)
	if err != nil {
		t.Fatalf("first Client() returned error: %v", err)
	}

	// tbot writes atomically via rename; the file can briefly be absent. A
	// working client must not be thrown away over a transient read failure.
	if err := os.Remove(path); err != nil {
		t.Fatalf("removing identity file: %v", err)
	}
	clock.advance(DefaultCheckInterval + time.Second)

	second, err := p.Client(ctx)
	if err != nil {
		t.Fatalf("Client() returned error while the identity file was missing: %v", err)
	}
	if second != first {
		t.Error("Client() replaced a working client because the identity file was momentarily unreadable")
	}
	if got := closer.count(); got != 0 {
		t.Errorf("client closed %d times, want 0", got)
	}

	// Once the file reappears with new content the rotation is picked up on the
	// very next call: a failed check must not consume the check interval.
	writeIdentity(t, path, "identity-v2-rotated")
	third, err := p.Client(ctx)
	if err != nil {
		t.Fatalf("Client() returned error: %v", err)
	}
	if got := dialer.count(); got != 2 {
		t.Errorf("dial called %d times, want 2 once the rotated file reappeared", got)
	}
	if third == first {
		t.Error("Client() did not reconnect after the rotated identity file reappeared")
	}
}

func TestAmbientProfileNeverRechecks(t *testing.T) {
	p, dialer, _, clock := newTestProvider(t, "")
	ctx := context.Background()

	first, err := p.Client(ctx)
	if err != nil {
		t.Fatalf("Client() returned error: %v", err)
	}
	if got := dialer.files[0]; got != "" {
		t.Errorf("dial received identityFile %q, want the empty ambient-profile value", got)
	}

	clock.advance(24 * time.Hour)
	second, err := p.Client(ctx)
	if err != nil {
		t.Fatalf("Client() returned error: %v", err)
	}
	if got := dialer.count(); got != 1 {
		t.Errorf("dial called %d times, want 1: there is no identity file to watch", got)
	}
	if first != second {
		t.Error("Client() reconnected with no identity file to watch")
	}
}

func TestCloseReleasesClient(t *testing.T) {
	path := filepath.Join(t.TempDir(), "identity")
	writeIdentity(t, path, "identity-v1")

	p, dialer, closer, _ := newTestProvider(t, path)
	ctx := context.Background()

	first, err := p.Client(ctx)
	if err != nil {
		t.Fatalf("Client() returned error: %v", err)
	}
	if err := p.Close(); err != nil {
		t.Fatalf("Close() returned error: %v", err)
	}
	if got := closer.count(); got != 1 {
		t.Fatalf("Close() closed %d clients, want 1", got)
	}
	if closer.closed[0] != first {
		t.Error("Close() closed a client other than the one handed out")
	}
	// Close is idempotent.
	if err := p.Close(); err != nil {
		t.Fatalf("second Close() returned error: %v", err)
	}
	if got := closer.count(); got != 1 {
		t.Errorf("second Close() closed %d clients in total, want 1", got)
	}
	// After Close the provider dials again on demand.
	if _, err := p.Client(ctx); err != nil {
		t.Fatalf("Client() after Close returned error: %v", err)
	}
	if got := dialer.count(); got != 2 {
		t.Errorf("dial called %d times, want 2 after reuse following Close", got)
	}
}

func TestCloseWithoutClientIsNoop(t *testing.T) {
	p, _, closer, _ := newTestProvider(t, filepath.Join(t.TempDir(), "identity"))
	if err := p.Close(); err != nil {
		t.Fatalf("Close() on an unused provider returned error: %v", err)
	}
	if got := closer.count(); got != 0 {
		t.Errorf("Close() closed %d clients, want 0", got)
	}
}

func TestConcurrentClientCallsDialOnce(t *testing.T) {
	path := filepath.Join(t.TempDir(), "identity")
	writeIdentity(t, path, "identity-v1")

	p, dialer, _, _ := newTestProvider(t, path)
	ctx := context.Background()

	const goroutines = 32
	var wg sync.WaitGroup
	results := make([]*client.Client, goroutines)
	errs := make([]error, goroutines)
	start := make(chan struct{})
	for i := 0; i < goroutines; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			<-start
			results[i], errs[i] = p.Client(ctx)
		}(i)
	}
	close(start)
	wg.Wait()

	for i, err := range errs {
		if err != nil {
			t.Fatalf("goroutine %d: Client() returned error: %v", i, err)
		}
		if results[i] != results[0] {
			t.Fatalf("goroutine %d got a different client than goroutine 0", i)
		}
	}
	if got := dialer.count(); got != 1 {
		t.Errorf("dial called %d times under concurrent access, want 1", got)
	}
}

func TestNewProviderDoesNotDial(t *testing.T) {
	// The real defaults must be in place and nothing may touch the network
	// until Client is called.
	p := NewProvider("proxy.example.com:443", filepath.Join(t.TempDir(), "identity"))
	if p.dial == nil {
		t.Error("NewProvider left dial unset")
	}
	if p.now == nil {
		t.Error("NewProvider left now unset")
	}
	if p.closeClient == nil {
		t.Error("NewProvider left closeClient unset")
	}
	if p.checkInterval != DefaultCheckInterval {
		t.Errorf("NewProvider checkInterval = %s, want %s", p.checkInterval, DefaultCheckInterval)
	}
	if p.clt != nil {
		t.Error("NewProvider dialed a client eagerly")
	}
}
