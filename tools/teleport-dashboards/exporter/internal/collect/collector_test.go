package collect

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/gravitational/teleport/api/client"

	"github.com/jturner-teleport/teleport-usage/internal/exporter"
)

// ---------------------------------------------------------------------------
// fakes
// ---------------------------------------------------------------------------

// fakeCollector records how often it was called and does whatever fn says.
// It ignores the client entirely, so these tests never touch a real cluster.
type fakeCollector struct {
	name     string
	interval time.Duration
	fn       func(call int) error

	mu    sync.Mutex
	calls int
}

func (c *fakeCollector) Name() string            { return c.name }
func (c *fakeCollector) Interval() time.Duration { return c.interval }

func (c *fakeCollector) Collect(ctx context.Context, clt *client.Client) error {
	c.mu.Lock()
	c.calls++
	n := c.calls
	c.mu.Unlock()
	if c.fn == nil {
		return nil
	}
	return c.fn(n)
}

func (c *fakeCollector) callCount() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.calls
}

// fakeProvider hands out a nil client (the fake collectors never dereference
// it) or an error.
type fakeProvider struct {
	err error

	mu    sync.Mutex
	calls int
}

func (p *fakeProvider) Client(ctx context.Context) (*client.Client, error) {
	p.mu.Lock()
	p.calls++
	p.mu.Unlock()
	return nil, p.err
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

// runScheduler starts s in the background and returns a stop func that cancels
// it and waits for Run to return.
func runScheduler(t *testing.T, s *Scheduler) func() {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- s.Run(ctx) }()
	stopped := false
	stop := func() {
		if stopped {
			return
		}
		stopped = true
		cancel()
		select {
		case err := <-done:
			if err != nil {
				t.Errorf("Run returned %v, want nil on clean shutdown", err)
			}
		case <-time.After(2 * time.Second):
			t.Fatal("Run did not return within 2s of cancellation")
		}
	}
	t.Cleanup(stop)
	return stop
}

func metricValue(t *testing.T, r *exporter.Registry, name string, labels map[string]string) (float64, bool) {
	t.Helper()
	mfs, err := r.Gatherer().Gather()
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	for _, mf := range mfs {
		if mf.GetName() != name {
			continue
		}
	metrics:
		for _, m := range mf.GetMetric() {
			got := map[string]string{}
			for _, lp := range m.GetLabel() {
				got[lp.GetName()] = lp.GetValue()
			}
			for k, v := range labels {
				if got[k] != v {
					continue metrics
				}
			}
			switch {
			case m.Gauge != nil:
				return m.Gauge.GetValue(), true
			case m.Counter != nil:
				return m.Counter.GetValue(), true
			}
		}
	}
	return 0, false
}

func familyPresent(t *testing.T, r *exporter.Registry, name string) bool {
	t.Helper()
	mfs, err := r.Gatherer().Gather()
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	for _, mf := range mfs {
		if mf.GetName() == name {
			return true
		}
	}
	return false
}

// eventually polls cond until it is true or the deadline passes.
func eventually(t *testing.T, timeout time.Duration, msg string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatalf("timed out after %s waiting for: %s", timeout, msg)
}

func wantCollectorFailed(t *testing.T, r *exporter.Registry, name string, timeout time.Duration) {
	t.Helper()
	eventually(t, timeout, "collector "+name+" to be marked down", func() bool {
		v, ok := metricValue(t, r, "teleport_usage_collector_up", map[string]string{"collector": name})
		return ok && v == 0
	})
	n, ok := metricValue(t, r, "teleport_usage_collector_errors_total", map[string]string{"collector": name})
	if !ok || n < 1 {
		t.Errorf("collector %s: errors_total = %v (present=%v), want >= 1", name, n, ok)
	}
}

// ---------------------------------------------------------------------------
// tests
// ---------------------------------------------------------------------------

func TestCollectorErrorMarksFailure(t *testing.T) {
	reg := exporter.New("test", "v18.8.0")
	// Seed real data so we can prove the scheduler's failure path withdraws it
	// rather than leaving a confident zero behind.
	reg.SetResources(map[string]int{"node": 1, "app": 2, "kube": 1})

	c := &fakeCollector{
		name:     exporter.CollectorResources,
		interval: 20 * time.Millisecond,
		fn:       func(int) error { return errors.New("GetApplicationServers: connection refused") },
	}
	s := NewScheduler(reg, &fakeProvider{}, c)
	runScheduler(t, s)

	wantCollectorFailed(t, reg, exporter.CollectorResources, time.Second)

	if familyPresent(t, reg, "teleport_usage_protected_resources_total") {
		t.Error("protected_resources_total still published after the collector errored; it must be withdrawn, not zeroed")
	}
}

func TestPanickingCollectorDoesNotKillScheduler(t *testing.T) {
	reg := exporter.New("test", "v18.8.0")

	boom := &fakeCollector{
		name:     "boom",
		interval: 20 * time.Millisecond,
		fn:       func(int) error { panic("nil map read") },
	}
	healthy := &fakeCollector{
		name:     "healthy",
		interval: 20 * time.Millisecond,
	}

	s := NewScheduler(reg, &fakeProvider{}, boom, healthy)
	runScheduler(t, s)

	wantCollectorFailed(t, reg, "boom", time.Second)

	// The scheduler is still alive: the healthy collector keeps running and
	// the panicking one is retried rather than abandoned.
	eventually(t, time.Second, "healthy collector to keep collecting", func() bool {
		return healthy.callCount() >= 3
	})
	eventually(t, time.Second, "panicking collector to be retried", func() bool {
		return boom.callCount() >= 2
	})
	if v, ok := metricValue(t, reg, "teleport_usage_collector_up", map[string]string{"collector": "healthy"}); !ok || v != 1 {
		t.Errorf("healthy collector_up = %v (present=%v), want 1", v, ok)
	}
}

func TestClientProviderFailureMarksAllCollectorsFailed(t *testing.T) {
	reg := exporter.New("test", "v18.8.0")

	a := &fakeCollector{name: "alpha", interval: 20 * time.Millisecond}
	b := &fakeCollector{name: "bravo", interval: time.Hour} // never ticks on its own within the test

	p := &fakeProvider{err: errors.New("identity file expired")}
	s := NewScheduler(reg, p, a, b)
	// bravo's own goroutine is parked for the whole test, so the only thing
	// that can mark it failed is alpha's tick discovering the dead client.
	s.jitter = func(name string, _ time.Duration) time.Duration {
		if name == "bravo" {
			return time.Hour
		}
		return 0
	}
	runScheduler(t, s)

	// A dead client is not one collector's problem — every collector's data is
	// unknown, so every collector must say so.
	wantCollectorFailed(t, reg, "alpha", time.Second)
	wantCollectorFailed(t, reg, "bravo", time.Second)

	if n := a.callCount(); n != 0 {
		t.Errorf("alpha.Collect called %d times with no client available", n)
	}
	if n := b.callCount(); n != 0 {
		t.Errorf("bravo.Collect called %d times with no client available", n)
	}
}

func TestRunsImmediatelyThenOnInterval(t *testing.T) {
	reg := exporter.New("test", "v18.8.0")

	c := &fakeCollector{name: "tick", interval: 20 * time.Millisecond}
	s := NewScheduler(reg, &fakeProvider{}, c)

	start := time.Now()
	runScheduler(t, s)

	// Immediately (modulo up to 10% jitter = 2ms), not after a full interval.
	eventually(t, 200*time.Millisecond, "first collection at startup", func() bool {
		return c.callCount() >= 1
	})
	if elapsed := time.Since(start); elapsed > 100*time.Millisecond {
		t.Errorf("first collection took %s; it should run at startup, not after a full interval", elapsed)
	}

	// And then it keeps ticking.
	eventually(t, 500*time.Millisecond, "repeated collections on the interval", func() bool {
		return c.callCount() >= 4
	})

	if v, ok := metricValue(t, reg, "teleport_usage_collector_up", map[string]string{"collector": "tick"}); !ok || v != 1 {
		t.Errorf("collector_up = %v (present=%v), want 1", v, ok)
	}
	if _, ok := metricValue(t, reg, "teleport_usage_collector_last_success_timestamp_seconds", map[string]string{"collector": "tick"}); !ok {
		t.Error("last_success_timestamp_seconds not published for a succeeding collector")
	}
}

func TestContextCancellationStopsRun(t *testing.T) {
	reg := exporter.New("test", "v18.8.0")

	c := &fakeCollector{name: "slow", interval: time.Hour}
	s := NewScheduler(reg, &fakeProvider{}, c)
	s.jitter = noJitter

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- s.Run(ctx) }()

	eventually(t, time.Second, "the startup collection", func() bool { return c.callCount() >= 1 })

	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Errorf("Run returned %v, want nil on clean shutdown", err)
		}
	case <-time.After(500 * time.Millisecond):
		t.Fatal("Run did not return promptly after cancellation")
	}
}

// A scheduler with no collectors must still block until ctx is done, rather
// than returning instantly and letting main think it has shut down.
func TestRunWithNoCollectorsBlocksUntilCancelled(t *testing.T) {
	s := NewScheduler(exporter.New("test", "v18.8.0"), &fakeProvider{})

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- s.Run(ctx) }()

	select {
	case <-done:
		t.Fatal("Run returned before the context was cancelled")
	case <-time.After(50 * time.Millisecond):
	}

	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Errorf("Run returned %v, want nil", err)
		}
	case <-time.After(500 * time.Millisecond):
		t.Fatal("Run did not return after cancellation")
	}
}

func noJitter(string, time.Duration) time.Duration { return 0 }

func TestStartupJitterIsBounded(t *testing.T) {
	for _, interval := range []time.Duration{0, time.Millisecond, 20 * time.Millisecond, 5 * time.Minute, time.Hour} {
		for i := 0; i < 200; i++ {
			j := startupJitter(interval)
			if j < 0 {
				t.Fatalf("interval %s: jitter %s is negative", interval, j)
			}
			if bound := interval / 10; j > bound {
				t.Fatalf("interval %s: jitter %s exceeds 10%% (%s)", interval, j, bound)
			}
			// And is capped absolutely, so an hourly collector still
			// publishes at startup rather than six minutes later.
			if j > maxStartupJitter {
				t.Fatalf("interval %s: jitter %s exceeds the %s cap", interval, j, maxStartupJitter)
			}
		}
	}
}

func TestNonPositiveIntervalFallsBackToDefault(t *testing.T) {
	reg := exporter.New("test", "v18.8.0")
	c := &fakeCollector{name: "zero", interval: 0}
	s := NewScheduler(reg, &fakeProvider{}, c)
	s.jitter = noJitter
	runScheduler(t, s)

	// It still runs once at startup; it just does not spin.
	eventually(t, time.Second, "startup collection with a zero interval", func() bool {
		return c.callCount() >= 1
	})
	time.Sleep(50 * time.Millisecond)
	if n := c.callCount(); n > 1 {
		t.Errorf("collector with interval 0 ran %d times in 50ms; it must fall back to the default interval, not busy-loop", n)
	}
}

// Compile-time proof that the fakes satisfy the interfaces downstream
// collectors will implement.
var (
	_ Collector      = (*fakeCollector)(nil)
	_ ClientProvider = (*fakeProvider)(nil)
)
