package exporter

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// errTest stands in for any collector failure; the reason is never a label.
var errTest = errors.New("collector failed")

// newTestServer wires a Server over a fresh registry, as main does.
func newTestServer(t *testing.T) (*Server, *Registry) {
	t.Helper()
	r := New("test-version", "test-api")
	return NewServer(r), r
}

func TestMetricsEndpointServesTheRegistry(t *testing.T) {
	s, r := newTestServer(t)
	r.SetResources(map[string]int{"node": 1, "app": 2})

	rec := httptest.NewRecorder()
	s.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/metrics", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("GET /metrics = %d, want 200", rec.Code)
	}
	body := rec.Body.String()
	for _, want := range []string{
		`teleport_usage_protected_resources{kind="app"} 2`,
		`teleport_usage_protected_resources{kind="node"} 1`,
		`teleport_usage_protected_resources_total 3`,
	} {
		if !strings.Contains(body, want) {
			t.Errorf("/metrics missing %q", want)
		}
	}
}

func TestHealthzIsLivenessNotReadiness(t *testing.T) {
	// Liveness must stay 200 even when every collector is failing: the process
	// is alive and restarting it would not fix a broken upstream. Conflating
	// the two turns a Teleport outage into a pod crash-loop.
	s, r := newTestServer(t)
	r.MarkFailure(CollectorResources, errTest)

	rec := httptest.NewRecorder()
	s.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /healthz with a failing collector = %d, want 200", rec.Code)
	}
}

func TestReadyzIsNotReadyBeforeAnyCollectionSucceeds(t *testing.T) {
	// A freshly started exporter has nothing to report. Serving 200 here would
	// let Kubernetes mark the pod Ready while /metrics is empty, which reads
	// downstream as "no protected resources" rather than "not measured yet" --
	// the exact ambiguity this exporter exists to remove.
	s, _ := newTestServer(t)

	rec := httptest.NewRecorder()
	s.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("GET /readyz before first success = %d, want 503", rec.Code)
	}
}

func TestReadyzBecomesReadyAfterFirstSuccess(t *testing.T) {
	s, r := newTestServer(t)
	r.SetResources(map[string]int{"node": 1})

	rec := httptest.NewRecorder()
	s.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /readyz after a successful collection = %d, want 200", rec.Code)
	}
}

func TestReadyzStaysReadyAfterALaterFailure(t *testing.T) {
	// Readiness is "has this exporter ever produced data", not "is everything
	// healthy right now". A transient Teleport blip should withdraw the
	// affected metrics -- which it does -- not pull the pod out of service and
	// hide the collector_up signal that says what is wrong.
	s, r := newTestServer(t)
	r.SetResources(map[string]int{"node": 1})
	r.MarkFailure(CollectorResources, errTest)

	rec := httptest.NewRecorder()
	s.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /readyz after a later failure = %d, want 200", rec.Code)
	}
}

func TestUnknownPathIs404(t *testing.T) {
	s, _ := newTestServer(t)
	rec := httptest.NewRecorder()
	s.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/nope", nil))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("GET /nope = %d, want 404", rec.Code)
	}
}

func TestRootListsTheEndpoints(t *testing.T) {
	s, _ := newTestServer(t)
	rec := httptest.NewRecorder()
	s.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("GET / = %d, want 200", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "/metrics") {
		t.Error("GET / should point at /metrics")
	}
}
