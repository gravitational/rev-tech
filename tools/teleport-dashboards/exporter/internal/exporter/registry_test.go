package exporter_test

import (
	"errors"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus/testutil"
	dto "github.com/prometheus/client_model/go"

	"github.com/jturner-teleport/teleport-usage/internal/exporter"
)

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

func gather(t *testing.T, r *exporter.Registry) []*dto.MetricFamily {
	t.Helper()
	mfs, err := r.Gatherer().Gather()
	if err != nil {
		t.Fatalf("Gather: %v", err)
	}
	return mfs
}

func family(t *testing.T, r *exporter.Registry, name string) *dto.MetricFamily {
	t.Helper()
	for _, mf := range gather(t, r) {
		if mf.GetName() == name {
			return mf
		}
	}
	return nil
}

// find returns the single metric in family name whose labels are a superset of
// the wanted labels, or nil if there is none.
func find(t *testing.T, r *exporter.Registry, name string, labels map[string]string) *dto.Metric {
	t.Helper()
	mf := family(t, r, name)
	if mf == nil {
		return nil
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
		return m
	}
	return nil
}

// value returns the gauge/counter value and whether the series exists at all.
// The distinction between (0, true) and (0, false) is the entire point of this
// package: a withdrawn metric must be absent, not zero.
func value(t *testing.T, r *exporter.Registry, name string, labels map[string]string) (float64, bool) {
	t.Helper()
	m := find(t, r, name, labels)
	if m == nil {
		return 0, false
	}
	switch {
	case m.Gauge != nil:
		return m.Gauge.GetValue(), true
	case m.Counter != nil:
		return m.Counter.GetValue(), true
	default:
		t.Fatalf("metric %s is neither gauge nor counter", name)
		return 0, false
	}
}

func mustValue(t *testing.T, r *exporter.Registry, name string, labels map[string]string) float64 {
	t.Helper()
	v, ok := value(t, r, name, labels)
	if !ok {
		t.Fatalf("metric %s%v is absent, expected it to be present", name, labels)
	}
	return v
}

func wantValue(t *testing.T, r *exporter.Registry, name string, labels map[string]string, want float64) {
	t.Helper()
	if got := mustValue(t, r, name, labels); got != want {
		t.Errorf("%s%v = %v, want %v", name, labels, got, want)
	}
}

func wantAbsent(t *testing.T, r *exporter.Registry, name string, labels map[string]string) {
	t.Helper()
	if v, ok := value(t, r, name, labels); ok {
		t.Errorf("%s%v is present with value %v, want it to be ABSENT (withdrawn, not zeroed)", name, labels, v)
	}
}

const (
	mResources      = "teleport_usage_protected_resources"
	mResourcesTotal = "teleport_usage_protected_resources_total"
	mBots           = "teleport_usage_bots"
	mBotInstances   = "teleport_usage_bot_instances"
	mUp             = "teleport_usage_collector_up"
	mLastSuccess    = "teleport_usage_collector_last_success_timestamp_seconds"
	mErrors         = "teleport_usage_collector_errors_total"
	mBuildInfo      = "teleport_usage_build_info"
	mMismatch       = "teleport_usage_version_mismatch"
)

// ---------------------------------------------------------------------------
// The most important test in the package.
// ---------------------------------------------------------------------------

// TestFailedCollectorWithdrawsMetricsRatherThanZeroing is the regression test
// for the real failure that motivated this whole design: a broken collector
// published zeros, which looked exactly like an empty cluster, and the
// dashboard showed a confident 0 protected resources for a month while the
// cluster had 4.
func TestFailedCollectorWithdrawsMetricsRatherThanZeroing(t *testing.T) {
	r := exporter.New("v1.0.0", "v18.8.0")

	r.SetResources(map[string]int{"node": 1, "app": 2, "kube": 1})

	wantValue(t, r, mResourcesTotal, nil, 4)
	wantValue(t, r, mResources, map[string]string{"kind": "node"}, 1)
	wantValue(t, r, mResources, map[string]string{"kind": "app"}, 2)
	wantValue(t, r, mResources, map[string]string{"kind": "kube"}, 1)
	wantValue(t, r, mUp, map[string]string{"collector": "resources"}, 1)

	lastSuccess := mustValue(t, r, mLastSuccess, map[string]string{"collector": "resources"})
	if lastSuccess <= 0 {
		t.Errorf("last success timestamp = %v, want a real unix time", lastSuccess)
	}

	r.MarkFailure("resources", errors.New("connection refused"))

	// The resource series must be gone from /metrics entirely.
	n, err := testutil.GatherAndCount(r.Gatherer(), mResources, mResourcesTotal)
	if err != nil {
		t.Fatalf("GatherAndCount: %v", err)
	}
	if n != 0 {
		t.Errorf("after failure, %d resource series remain; want 0 (metrics must be withdrawn, not set to 0)", n)
	}

	// Belt and braces: no family, and specifically no present-with-value-0.
	if mf := family(t, r, mResources); mf != nil {
		t.Errorf("metric family %s still present after failure: %v", mResources, mf)
	}
	if mf := family(t, r, mResourcesTotal); mf != nil {
		t.Errorf("metric family %s still present after failure: %v", mResourcesTotal, mf)
	}
	wantAbsent(t, r, mResources, map[string]string{"kind": "node"})
	wantAbsent(t, r, mResourcesTotal, nil)

	// Health must say so, loudly.
	wantValue(t, r, mUp, map[string]string{"collector": "resources"}, 0)
	wantValue(t, r, mErrors, map[string]string{"collector": "resources"}, 1)

	// The last success timestamp is retained so staleness is measurable.
	wantValue(t, r, mLastSuccess, map[string]string{"collector": "resources"}, lastSuccess)
}

func TestRecoveryAfterFailure(t *testing.T) {
	r := exporter.New("v1.0.0", "v18.8.0")

	r.SetResources(map[string]int{"node": 1, "app": 2, "kube": 1})
	r.MarkFailure("resources", errors.New("boom"))
	wantAbsent(t, r, mResourcesTotal, nil)

	r.SetResources(map[string]int{"node": 3})

	wantValue(t, r, mResourcesTotal, nil, 3)
	wantValue(t, r, mResources, map[string]string{"kind": "node"}, 3)
	wantValue(t, r, mUp, map[string]string{"collector": "resources"}, 1)
	// The error count is cumulative; recovery does not erase history.
	wantValue(t, r, mErrors, map[string]string{"collector": "resources"}, 1)

	// Kinds that vanished from the source must not linger as stale series.
	wantAbsent(t, r, mResources, map[string]string{"kind": "app"})
	wantAbsent(t, r, mResources, map[string]string{"kind": "kube"})
}

func TestFailureOfOneCollectorDoesNotAffectAnother(t *testing.T) {
	r := exporter.New("v1.0.0", "v18.8.0")

	r.SetResources(map[string]int{"node": 1})
	r.SetMWI(3, 7)

	r.MarkFailure("resources", errors.New("boom"))

	wantAbsent(t, r, mResourcesTotal, nil)
	wantValue(t, r, mBots, nil, 3)
	wantValue(t, r, mBotInstances, nil, 7)
	wantValue(t, r, mUp, map[string]string{"collector": "mwi"}, 1)
	// mwi's error counter exists (so rate() has a prior sample) but must not
	// have moved: only resources failed.
	wantValue(t, r, mErrors, map[string]string{"collector": "mwi"}, 0)
}

func TestMarkFailureWithdrawsEachCollectorsOwnMetrics(t *testing.T) {
	seed := func(r *exporter.Registry) {
		r.SetResources(map[string]int{"node": 1})
		r.SetMWI(3, 7)
		r.SetAuthPref(exporter.AuthPref{
			SecondFactorEnforced: true,
			SecondFactors:        []string{"otp"},
			DeviceTrustMode:      "off",
		})
	}

	cases := map[string][]string{
		"resources": {mResources, mResourcesTotal},
		"mwi":       {mBots, mBotInstances},
		"authpref": {
			"teleport_usage_auth_second_factor_enforced",
			"teleport_usage_auth_second_factor_enabled",
			"teleport_usage_auth_webauthn_configured",
			"teleport_usage_auth_require_session_mfa",
			"teleport_usage_auth_device_trust_mode",
		},
	}

	for collector, names := range cases {
		t.Run(collector, func(t *testing.T) {
			r := exporter.New("v1.0.0", "v18.8.0")
			seed(r)
			for _, n := range names {
				if family(t, r, n) == nil {
					t.Fatalf("%s missing before failure", n)
				}
			}
			r.MarkFailure(collector, errors.New("boom"))
			for _, n := range names {
				if mf := family(t, r, n); mf != nil {
					t.Errorf("%s still present after %s failed: %v", n, collector, mf)
				}
			}
			wantValue(t, r, mUp, map[string]string{"collector": collector}, 0)
		})
	}
}

func TestBuildInfoAlwaysOne(t *testing.T) {
	r := exporter.New("v1.2.3", "v18.8.0")

	wantValue(t, r, mBuildInfo, map[string]string{
		"version":              "v1.2.3",
		"teleport_api_version": "v18.8.0",
	}, 1)

	r.SetBuildInfo("v1.2.3", "v18.8.0", "example.teleport.sh")

	wantValue(t, r, mBuildInfo, map[string]string{
		"version":              "v1.2.3",
		"teleport_api_version": "v18.8.0",
		"cluster":              "example.teleport.sh",
	}, 1)

	// Exactly one build_info series — the pre-cluster one must be replaced,
	// not accumulated alongside.
	if mf := family(t, r, mBuildInfo); mf == nil || len(mf.GetMetric()) != 1 {
		t.Fatalf("want exactly 1 build_info series, got %v", mf)
	}

	// Never withdrawn, never anything but 1.
	r.MarkFailure("resources", errors.New("boom"))
	wantValue(t, r, mBuildInfo, map[string]string{"cluster": "example.teleport.sh"}, 1)
}

func TestAuthPrefMapsAllFields(t *testing.T) {
	r := exporter.New("v1.0.0", "v18.8.0")

	r.SetAuthPref(exporter.AuthPref{
		SecondFactorEnforced: true,
		SecondFactors:        []string{"otp", "webauthn"},
		WebauthnConfigured:   true,
		RequireSessionMFA:    true,
		DeviceTrustMode:      "optional",
	})

	wantValue(t, r, "teleport_usage_auth_second_factor_enforced", nil, 1)
	wantValue(t, r, "teleport_usage_auth_webauthn_configured", nil, 1)
	wantValue(t, r, "teleport_usage_auth_require_session_mfa", nil, 1)

	// Only the listed factors are 1; the other known factors are explicitly 0.
	wantValue(t, r, "teleport_usage_auth_second_factor_enabled", map[string]string{"type": "otp"}, 1)
	wantValue(t, r, "teleport_usage_auth_second_factor_enabled", map[string]string{"type": "webauthn"}, 1)
	wantValue(t, r, "teleport_usage_auth_second_factor_enabled", map[string]string{"type": "sso"}, 0)

	// Exactly one device trust mode is 1.
	wantValue(t, r, "teleport_usage_auth_device_trust_mode", map[string]string{"mode": "optional"}, 1)
	wantValue(t, r, "teleport_usage_auth_device_trust_mode", map[string]string{"mode": "off"}, 0)
	wantValue(t, r, "teleport_usage_auth_device_trust_mode", map[string]string{"mode": "required"}, 0)

	wantValue(t, r, mUp, map[string]string{"collector": "authpref"}, 1)

	// The all-off posture is a real answer, not a missing one: every field
	// still reports, all zero.
	r.SetAuthPref(exporter.AuthPref{DeviceTrustMode: "off"})
	wantValue(t, r, "teleport_usage_auth_second_factor_enforced", nil, 0)
	wantValue(t, r, "teleport_usage_auth_second_factor_enabled", map[string]string{"type": "otp"}, 0)
	wantValue(t, r, "teleport_usage_auth_webauthn_configured", nil, 0)
	wantValue(t, r, "teleport_usage_auth_require_session_mfa", nil, 0)
	wantValue(t, r, "teleport_usage_auth_device_trust_mode", map[string]string{"mode": "off"}, 1)
	wantValue(t, r, "teleport_usage_auth_device_trust_mode", map[string]string{"mode": "optional"}, 0)
}

func TestMarkSuccessAndFailureHealthAccounting(t *testing.T) {
	r := exporter.New("v1.0.0", "v18.8.0")

	before := float64(time.Now().Unix())
	r.MarkSuccess("mau")
	wantValue(t, r, mUp, map[string]string{"collector": "mau"}, 1)
	if ts := mustValue(t, r, mLastSuccess, map[string]string{"collector": "mau"}); ts < before {
		t.Errorf("last success %v predates the call (%v)", ts, before)
	}

	r.MarkFailure("mau", errors.New("a"))
	r.MarkFailure("mau", errors.New("b"))
	wantValue(t, r, mUp, map[string]string{"collector": "mau"}, 0)
	wantValue(t, r, mErrors, map[string]string{"collector": "mau"}, 2)

	r.MarkSuccess("mau")
	wantValue(t, r, mUp, map[string]string{"collector": "mau"}, 1)
	wantValue(t, r, mErrors, map[string]string{"collector": "mau"}, 2)
}

func TestSetVersionMismatch(t *testing.T) {
	r := exporter.New("v1.0.0", "v18.8.0")

	// Always present, so an alert on it does not need absent().
	wantValue(t, r, mMismatch, nil, 0)

	r.SetVersionMismatch(true)
	wantValue(t, r, mMismatch, nil, 1)

	r.SetVersionMismatch(false)
	wantValue(t, r, mMismatch, nil, 0)
}

// TestMetricTypesFollowNamingRules guards decision D5: gauges carry no _total
// suffix and counters do. Teleport itself violates this and it cost us a real
// dashboard bug.
func TestMetricTypesFollowNamingRules(t *testing.T) {
	r := exporter.New("v1.0.0", "v18.8.0")
	r.SetResources(map[string]int{"node": 1})
	r.SetMWI(1, 1)
	r.SetAuthPref(exporter.AuthPref{DeviceTrustMode: "off"})
	r.MarkFailure("mau", errors.New("boom"))

	wantType := map[string]dto.MetricType{
		mResources:      dto.MetricType_GAUGE,
		mResourcesTotal: dto.MetricType_GAUGE, // a sum across kinds, not a counter
		mBots:           dto.MetricType_GAUGE,
		mBotInstances:   dto.MetricType_GAUGE,
		mUp:             dto.MetricType_GAUGE,
		mLastSuccess:    dto.MetricType_GAUGE,
		mErrors:         dto.MetricType_COUNTER,
		mBuildInfo:      dto.MetricType_GAUGE,
		mMismatch:       dto.MetricType_GAUGE,
	}
	for name, want := range wantType {
		mf := family(t, r, name)
		if mf == nil {
			t.Errorf("%s absent", name)
			continue
		}
		if mf.GetType() != want {
			t.Errorf("%s is %v, want %v", name, mf.GetType(), want)
		}
	}

	// Nothing except the errors counter may end in _total, and nothing that
	// ends in _total may be a counter except that one.
	for _, mf := range gather(t, r) {
		isTotal := len(mf.GetName()) > 6 && mf.GetName()[len(mf.GetName())-6:] == "_total"
		if mf.GetType() == dto.MetricType_COUNTER && !isTotal {
			t.Errorf("counter %s must end in _total", mf.GetName())
		}
	}
}

func TestConcurrentSettersAndGathers(t *testing.T) {
	r := exporter.New("v1.0.0", "v18.8.0")
	done := make(chan struct{})
	go func() {
		defer close(done)
		for i := 0; i < 200; i++ {
			r.SetResources(map[string]int{"node": i})
			r.MarkFailure("resources", errors.New("boom"))
			r.SetMWI(i, i)
		}
	}()
	for i := 0; i < 200; i++ {
		if _, err := r.Gatherer().Gather(); err != nil {
			t.Fatalf("Gather: %v", err)
		}
	}
	<-done
}
