// Package exporter owns every metric this binary publishes.
//
// The design exists to prevent one specific, real failure. The tracker this
// replaces did:
//
//	apps, err := clt.GetApplicationServers(ctx, "default")
//	if err != nil {
//	    log.Printf("[ERROR] Failed to fetch applications: %v", err)
//	    return                       // swallowed
//	}
//
// The caller never checked whether any fetch had failed, wrote its snapshot
// anyway with zero counts, and logged "Usage report updated successfully". For
// a month the dashboard showed a confident 0 protected resources while the
// cluster actually had 4. Nothing detected it, because a broken collector and
// an empty cluster produce identical output.
//
// So: a collector that fails WITHDRAWS its metrics rather than publishing
// zeros. Prometheus then records staleness and the panel reads "No data".
// Unknown and zero are different states, all the way to the panel. Set(0) is
// never used as a failure signal anywhere in this package.
package exporter

import (
	"slices"
	"sync"
	"time"

	"github.com/prometheus/client_golang/prometheus"
)

// Collector names. These appear as the `collector` label on the health
// metrics, so they are part of the metric contract.
const (
	CollectorResources = "resources"
	CollectorMWI       = "mwi"
	CollectorAuthPref  = "authpref"
)

// knownSecondFactors is the closed set of second-factor types we always report
// on, so a panel can distinguish "otp is off" (0) from "we could not tell"
// (series absent because the collector failed).
var knownSecondFactors = []string{"otp", "webauthn", "sso"}

// knownDeviceTrustModes is the equivalent closed set for device trust.
var knownDeviceTrustModes = []string{"off", "optional", "required"}

// AuthPref is the MFA/device-trust posture of the cluster, flattened for
// export.
type AuthPref struct {
	SecondFactorEnforced bool
	SecondFactors        []string // "otp","webauthn","sso"
	WebauthnConfigured   bool
	RequireSessionMFA    bool
	DeviceTrustMode      string // "off","optional","required"
}

// resettable is the withdrawal mechanism. Every data metric is a *GaugeVec
// (even the label-less ones) purely so that Reset can delete its child series,
// making the metric genuinely disappear from /metrics instead of reporting 0.
type resettable interface {
	Reset()
}

// Registry owns every exported metric. A collector that fails WITHDRAWS its
// metrics rather than publishing zeros, so Prometheus records staleness and the
// panel reads "No data" instead of a confident zero.
type Registry struct {
	reg *prometheus.Registry

	// mu guards the read-modify-write sequences below (Reset followed by Set
	// must be atomic with respect to a concurrent Gather).
	mu sync.Mutex

	// everSucceeded backs Ready(). It latches on the first successful
	// collection and never clears: readiness answers "has this exporter ever
	// produced data", not "is everything healthy now".
	everSucceeded bool

	// resources collector
	protectedResources      *prometheus.GaugeVec
	protectedResourcesTotal *prometheus.GaugeVec

	// mwi collector
	bots         *prometheus.GaugeVec
	botInstances *prometheus.GaugeVec

	// authpref collector
	secondFactorEnforced *prometheus.GaugeVec
	secondFactorEnabled  *prometheus.GaugeVec
	webauthnConfigured   *prometheus.GaugeVec
	requireSessionMFA    *prometheus.GaugeVec
	deviceTrustMode      *prometheus.GaugeVec

	// owned maps a collector name to the metrics withdrawn when it fails.
	owned map[string][]resettable

	// Health metrics. These are never withdrawn — they are how a withdrawal
	// is explained.
	collectorUp          *prometheus.GaugeVec
	collectorLastSuccess *prometheus.GaugeVec
	collectorErrors      *prometheus.CounterVec
	buildInfo            *prometheus.GaugeVec
	versionMismatch      prometheus.Gauge

	// now is overridable in tests; nil means time.Now.
	now func() time.Time
}

// New builds a Registry with its own prometheus.Registry (no default Go or
// process collectors, so the output is exactly the documented contract) and
// seeds build_info with the version the binary was compiled against. The
// cluster label is filled in later by SetBuildInfo, once Ping has told us
// which cluster we are talking to.
func New(version, apiVersion string) *Registry {
	r := &Registry{
		reg: prometheus.NewRegistry(),

		protectedResources: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "teleport_usage_protected_resources",
			Help: "Protected resources by kind. Absent when the resources collector is failing — absent means unknown, not zero.",
		}, []string{"kind"}),
		// NOTE: protected_resources_total is a GAUGE despite the _total
		// suffix. It is a total ACROSS KINDS at a point in time, not a
		// monotonic counter. This deliberately contradicts the convention
		// applied to every other metric here (see collector_errors_total,
		// which is a real counter); the name is fixed by the metric contract.
		protectedResourcesTotal: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "teleport_usage_protected_resources_total",
			Help: "Total protected resources across all kinds. A gauge, not a counter, despite the _total suffix. Absent when the resources collector is failing.",
		}, nil),

		bots: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "teleport_usage_bots",
			Help: "Machine & Workload Identity bots. Absent when the mwi collector is failing.",
		}, nil),
		botInstances: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "teleport_usage_bot_instances",
			Help: "Machine & Workload Identity bot instances. Absent when the mwi collector is failing.",
		}, nil),

		secondFactorEnforced: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "teleport_usage_auth_second_factor_enforced",
			Help: "1 if a second factor is enforced cluster-wide, 0 if not. Absent when the authpref collector is failing.",
		}, nil),
		secondFactorEnabled: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "teleport_usage_auth_second_factor_enabled",
			Help: "1 if the given second factor type is enabled, 0 if not. Absent when the authpref collector is failing.",
		}, []string{"type"}),
		webauthnConfigured: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "teleport_usage_auth_webauthn_configured",
			Help: "1 if WebAuthn is configured, 0 if not. Absent when the authpref collector is failing.",
		}, nil),
		requireSessionMFA: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "teleport_usage_auth_require_session_mfa",
			Help: "1 if per-session MFA is required cluster-wide, 0 if not. Absent when the authpref collector is failing.",
		}, nil),
		deviceTrustMode: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "teleport_usage_auth_device_trust_mode",
			Help: "1 for the active device trust mode, 0 for the others. Absent when the authpref collector is failing.",
		}, []string{"mode"}),

		collectorUp: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "teleport_usage_collector_up",
			Help: "1 if the collector's last run succeeded, 0 if it failed. When this is 0 the collector's data metrics are withdrawn.",
		}, []string{"collector"}),
		collectorLastSuccess: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "teleport_usage_collector_last_success_timestamp_seconds",
			Help: "Unix timestamp of the collector's last successful run. Retained across failures so staleness is measurable.",
		}, []string{"collector"}),
		collectorErrors: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "teleport_usage_collector_errors_total",
			Help: "Cumulative collector failures. A real counter.",
		}, []string{"collector"}),
		buildInfo: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "teleport_usage_build_info",
			Help: "Always 1. Carries the exporter version, the Teleport API version it was built against, and the cluster name as labels.",
		}, []string{"version", "teleport_api_version", "cluster"}),
		versionMismatch: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "teleport_usage_version_mismatch",
			Help: "1 if the Teleport server's major/minor differs from the API version this binary was built against. A mismatched binary under-counts silently.",
		}),

		now: time.Now,
	}

	r.owned = map[string][]resettable{
		CollectorResources: {r.protectedResources, r.protectedResourcesTotal},
		CollectorMWI:       {r.bots, r.botInstances},
		CollectorAuthPref: {
			r.secondFactorEnforced,
			r.secondFactorEnabled,
			r.webauthnConfigured,
			r.requireSessionMFA,
			r.deviceTrustMode,
		},
	}

	r.reg.MustRegister(
		r.protectedResources,
		r.protectedResourcesTotal,
		r.bots,
		r.botInstances,
		r.secondFactorEnforced,
		r.secondFactorEnabled,
		r.webauthnConfigured,
		r.requireSessionMFA,
		r.deviceTrustMode,
		r.collectorUp,
		r.collectorLastSuccess,
		r.collectorErrors,
		r.buildInfo,
		r.versionMismatch,
	)

	r.buildInfo.WithLabelValues(version, apiVersion, "").Set(1)
	r.versionMismatch.Set(0)

	return r
}

// Gatherer exposes the metrics for /metrics and for tests.
func (r *Registry) Gatherer() prometheus.Gatherer { return r.reg }

// SetResources publishes the protected-resource inventory and marks the
// resources collector healthy. Kinds absent from byKind are withdrawn rather
// than left behind as stale series.
func (r *Registry) SetResources(byKind map[string]int) {
	r.mu.Lock()
	defer r.mu.Unlock()

	r.protectedResources.Reset()
	total := 0
	for kind, n := range byKind {
		r.protectedResources.WithLabelValues(kind).Set(float64(n))
		total += n
	}
	r.protectedResourcesTotal.WithLabelValues().Set(float64(total))

	r.markSuccess(CollectorResources)
}

// SetMWI publishes bot and bot-instance counts and marks the mwi collector
// healthy.
func (r *Registry) SetMWI(bots, botInstances int) {
	r.mu.Lock()
	defer r.mu.Unlock()

	r.bots.WithLabelValues().Set(float64(bots))
	r.botInstances.WithLabelValues().Set(float64(botInstances))

	r.markSuccess(CollectorMWI)
}

// SetAuthPref publishes the MFA/device-trust posture and marks the authpref
// collector healthy.
//
// Every known second-factor type and device-trust mode is emitted, including
// the ones that are off, so a panel can tell "off" from "unknown": off is 0,
// unknown is the series not being there at all.
func (r *Registry) SetAuthPref(s AuthPref) {
	r.mu.Lock()
	defer r.mu.Unlock()

	r.secondFactorEnforced.WithLabelValues().Set(b2f(s.SecondFactorEnforced))
	r.webauthnConfigured.WithLabelValues().Set(b2f(s.WebauthnConfigured))
	r.requireSessionMFA.WithLabelValues().Set(b2f(s.RequireSessionMFA))

	enabled := make(map[string]bool, len(s.SecondFactors))
	for _, f := range s.SecondFactors {
		enabled[f] = true
	}
	r.secondFactorEnabled.Reset()
	for _, f := range knownSecondFactors {
		r.secondFactorEnabled.WithLabelValues(f).Set(b2f(enabled[f]))
	}
	// A type Teleport reports that we do not know about is still worth
	// exporting; silently dropping it is how under-counting starts.
	for _, f := range s.SecondFactors {
		if !slices.Contains(knownSecondFactors, f) {
			r.secondFactorEnabled.WithLabelValues(f).Set(1)
		}
	}

	mode := s.DeviceTrustMode
	r.deviceTrustMode.Reset()
	for _, m := range knownDeviceTrustModes {
		r.deviceTrustMode.WithLabelValues(m).Set(b2f(m == mode))
	}
	if mode != "" && !slices.Contains(knownDeviceTrustModes, mode) {
		r.deviceTrustMode.WithLabelValues(mode).Set(1)
	}

	r.markSuccess(CollectorAuthPref)
}

// MarkSuccess records that the collector ran successfully.
func (r *Registry) MarkSuccess(collector string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.markSuccess(collector)
}

// MarkFailure records a collector failure and WITHDRAWS that collector's data
// series, so /metrics stops reporting them entirely. The alternative —
// publishing zeros — is the bug this package exists to prevent.
//
// The last-success timestamp is deliberately left alone so that
// time() - last_success measures how stale the withdrawn data is.
//
// err is accepted for the caller's convenience and for future structured
// logging; it is intentionally not turned into a label, because unbounded
// error strings would blow up cardinality (decision D4).
func (r *Registry) MarkFailure(collector string, err error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	for _, m := range r.owned[collector] {
		m.Reset()
	}
	r.collectorUp.WithLabelValues(collector).Set(0)
	r.collectorErrors.WithLabelValues(collector).Inc()
}

// SetBuildInfo replaces the build_info series, adding the cluster name once it
// is known. The value is always 1.
func (r *Registry) SetBuildInfo(version, apiVersion, cluster string) {
	r.mu.Lock()
	defer r.mu.Unlock()

	r.buildInfo.Reset()
	r.buildInfo.WithLabelValues(version, apiVersion, cluster).Set(1)
}

// SetVersionMismatch reports whether the server version differs from the API
// version this binary was built against.
func (r *Registry) SetVersionMismatch(mismatch bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.versionMismatch.Set(b2f(mismatch))
}

// markSuccess assumes r.mu is held.
// Ready reports whether any collector has ever completed successfully. It is
// the readiness signal: before the first success there is nothing to serve, and
// an empty /metrics is indistinguishable from a cluster with no resources.
// Once true it stays true -- a later failure withdraws the affected series,
// which is a better signal than removing the pod from service.
func (r *Registry) Ready() bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.everSucceeded
}

func (r *Registry) markSuccess(collector string) {
	r.everSucceeded = true
	r.collectorUp.WithLabelValues(collector).Set(1)
	r.collectorLastSuccess.WithLabelValues(collector).Set(float64(r.now().Unix()))
	// Touch the counter so it exists at 0 rather than appearing out of
	// nowhere on the first failure — rate() needs a prior sample.
	r.collectorErrors.WithLabelValues(collector).Add(0)
}

func b2f(b bool) float64 {
	if b {
		return 1
	}
	return 0
}
