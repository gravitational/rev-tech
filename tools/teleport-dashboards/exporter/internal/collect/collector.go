// Package collect runs the individual usage collectors on their own cadences
// and reports each one's health into the exporter registry.
//
// The scheduler exists to make the failure mode in internal/exporter
// impossible to reach by accident: every path out of a collection — error,
// panic, or a client that cannot be built — ends in reg.MarkFailure, which
// withdraws that collector's metrics. There is no path that silently skips a
// collection and leaves stale or zeroed data behind.
package collect

import (
	"context"
	"fmt"
	"log/slog"
	"math/rand/v2"
	"runtime/debug"
	"sync"
	"time"

	"github.com/gravitational/teleport/api/client"

	"github.com/jturner-teleport/teleport-usage/internal/exporter"
)

// defaultInterval is used when a collector reports a non-positive interval.
// Without this a misconfigured collector would busy-loop against the Teleport
// API.
const defaultInterval = 5 * time.Minute

// jitterFraction is the share of the interval used to stagger each collector's
// first run, so that N collectors do not all hit the API in the same
// millisecond at startup.
const jitterFraction = 10 // i.e. up to interval/10

// maxStartupJitter caps the stagger in absolute terms. 10% of the hourly MAU
// collector's interval would be six minutes, which is not "immediately at
// startup" by any reading — the exporter would serve no MAU data for six
// minutes after every rollout. A few seconds is all de-stampeding needs.
const maxStartupJitter = 5 * time.Second

// Collector gathers one slice of usage data and publishes it via the registry
// setters. It must return a non-nil error if it could not measure what it was
// asked to measure — returning nil after a failed fetch is exactly the bug
// this package is built to prevent.
type Collector interface {
	Name() string
	Interval() time.Duration
	Collect(ctx context.Context, clt *client.Client) error
}

// ClientProvider hands out a currently-valid Teleport API client. It is an
// interface so the scheduler does not depend on how the client is built or
// how its identity is refreshed.
type ClientProvider interface {
	Client(ctx context.Context) (*client.Client, error)
}

// Scheduler runs each collector on its own interval in its own goroutine and
// records the outcome of every run against the registry.
type Scheduler struct {
	reg        *exporter.Registry
	clients    ClientProvider
	collectors []Collector
	log        *slog.Logger

	// jitter is a seam for tests that use long intervals and cannot wait out
	// a real stagger. Production always uses startupJitter.
	jitter func(collector string, interval time.Duration) time.Duration
}

// NewScheduler wires the collectors to the registry and the client provider.
func NewScheduler(reg *exporter.Registry, clients ClientProvider, cs ...Collector) *Scheduler {
	return &Scheduler{
		reg:        reg,
		clients:    clients,
		collectors: cs,
		log:        slog.Default(),
		jitter: func(_ string, interval time.Duration) time.Duration {
			return startupJitter(interval)
		},
	}
}

// Run starts every collector and blocks until ctx is done. It returns nil on a
// clean shutdown: cancellation is the normal way this stops.
func (s *Scheduler) Run(ctx context.Context) error {
	if len(s.collectors) == 0 {
		<-ctx.Done()
		return nil
	}

	var wg sync.WaitGroup
	for _, c := range s.collectors {
		wg.Add(1)
		go func(c Collector) {
			defer wg.Done()
			s.runCollector(ctx, c)
		}(c)
	}
	wg.Wait()
	return nil
}

// runCollector loops one collector until ctx is done: jitter, then collect
// immediately, then collect once per interval.
func (s *Scheduler) runCollector(ctx context.Context, c Collector) {
	interval := c.Interval()
	if interval <= 0 {
		s.log.Warn("collector reported a non-positive interval; using the default",
			"collector", c.Name(), "reported", interval, "using", defaultInterval)
		interval = defaultInterval
	}

	if j := s.jitter(c.Name(), interval); j > 0 {
		timer := time.NewTimer(j)
		select {
		case <-ctx.Done():
			timer.Stop()
			return
		case <-timer.C:
		}
	}

	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		// Run immediately (after jitter) rather than waiting a full interval,
		// so a fresh process publishes real data within seconds.
		s.collectOnce(ctx, c)

		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

// collectOnce performs a single collection and records its outcome. Every exit
// path marks either success or failure; none of them is silent.
func (s *Scheduler) collectOnce(ctx context.Context, c Collector) {
	if ctx.Err() != nil {
		return
	}

	clt, err := s.clients.Client(ctx)
	if err != nil {
		if ctx.Err() != nil {
			return
		}
		// A client we cannot build is not one collector's problem: nothing can
		// be measured, so every collector's data is unknown and every one of
		// them must withdraw. (This over-counts collector_errors_total when
		// several collectors tick during an outage — deliberately. Missing an
		// outage is far worse than counting it twice.)
		s.markAllFailed(fmt.Errorf("teleport client unavailable: %w", err))
		return
	}

	if err := s.safeCollect(ctx, c, clt); err != nil {
		if ctx.Err() != nil {
			// Shutting down; the collector was interrupted rather than broken.
			return
		}
		s.log.Error("collector failed; withdrawing its metrics", "collector", c.Name(), "error", err)
		s.reg.MarkFailure(c.Name(), err)
		return
	}

	// The collector's setter has already marked success; this covers
	// collectors that legitimately publish nothing on a given run.
	s.reg.MarkSuccess(c.Name())
}

// safeCollect turns a panicking collector into an ordinary error. A nil-map
// read in one collector must not take down the exporter and blind every
// dashboard at once.
func (s *Scheduler) safeCollect(ctx context.Context, c Collector, clt *client.Client) (err error) {
	defer func() {
		if p := recover(); p != nil {
			s.log.Error("collector panicked",
				"collector", c.Name(), "panic", p, "stack", string(debug.Stack()))
			err = fmt.Errorf("collector %s panicked: %v", c.Name(), p)
		}
	}()
	return c.Collect(ctx, clt)
}

// markAllFailed withdraws every collector's metrics.
func (s *Scheduler) markAllFailed(err error) {
	s.log.Error("no Teleport client available; withdrawing all collector metrics", "error", err)
	for _, c := range s.collectors {
		s.reg.MarkFailure(c.Name(), err)
	}
}

// startupJitter returns a random delay in [0, min(interval/10, 5s)] used to
// stagger collectors' first runs.
func startupJitter(interval time.Duration) time.Duration {
	bound := interval / jitterFraction
	if bound > maxStartupJitter {
		bound = maxStartupJitter
	}
	if bound <= 0 {
		return 0
	}
	return time.Duration(rand.Int64N(int64(bound) + 1))
}
