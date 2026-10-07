package exporter

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Server exposes the registry over HTTP.
//
// Liveness and readiness are deliberately different questions:
//
//   - /healthz is liveness. It is 200 whenever the process is running, even
//     with every collector failing. Restarting the exporter does not fix a
//     Teleport outage, and wiring liveness to upstream health turns an outage
//     into a crash-loop that destroys the collector_up signal explaining it.
//
//   - /readyz is "has this exporter ever produced data". It is 503 until the
//     first successful collection, so a pod that can never authenticate never
//     goes Ready. Without that, Kubernetes would mark it Ready while /metrics
//     is empty, and an empty /metrics reads downstream as "no protected
//     resources" rather than "not measured yet". That ambiguity is the whole
//     reason this exporter replaced its predecessor.
//
// Readiness deliberately does NOT flip back to false on a later failure. The
// registry already withdraws the affected series, which is the correct signal;
// pulling the pod out of service on top of that would hide it.
type Server struct {
	reg *Registry
}

// NewServer builds the HTTP surface for a registry.
func NewServer(reg *Registry) *Server {
	return &Server{reg: reg}
}

// Handler returns the mux, exported so tests can drive it without a socket.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()

	mux.Handle("/metrics", promhttp.HandlerFor(s.reg.Gatherer(), promhttp.HandlerOpts{
		// Surface encoding problems as a 500 rather than a silently truncated
		// scrape, which would look like metrics simply going away.
		ErrorHandling: promhttp.HTTPErrorOnError,
	}))

	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok\n"))
	})

	mux.HandleFunc("/readyz", func(w http.ResponseWriter, r *http.Request) {
		if !s.reg.Ready() {
			w.WriteHeader(http.StatusServiceUnavailable)
			_, _ = w.Write([]byte("no collector has succeeded yet\n"))
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok\n"))
	})

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = w.Write([]byte(`<html><head><title>teleport-usage exporter</title></head><body>
<h1>teleport-usage exporter</h1>
<ul>
<li><a href="/metrics">/metrics</a></li>
<li><a href="/healthz">/healthz</a> &mdash; liveness</li>
<li><a href="/readyz">/readyz</a> &mdash; ready once a collection has succeeded</li>
</ul>
</body></html>`))
	})

	return mux
}

// ListenAndServe runs until ctx is cancelled, then shuts down gracefully.
func (s *Server) ListenAndServe(ctx context.Context, addr string) error {
	srv := &http.Server{
		Addr:              addr,
		Handler:           s.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		slog.Info("serving metrics", "addr", addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
			return
		}
		errCh <- nil
	}()

	select {
	case err := <-errCh:
		if err != nil {
			return fmt.Errorf("metrics server: %w", err)
		}
		return nil
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := srv.Shutdown(shutdownCtx); err != nil {
			return fmt.Errorf("shutting down metrics server: %w", err)
		}
		return nil
	}
}
