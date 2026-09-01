package collect

import (
	"context"
	"errors"
	"os"
	"reflect"
	"slices"
	"testing"
	"time"

	"github.com/gravitational/teleport/api/client"
	"github.com/gravitational/teleport/api/constants"
	"github.com/gravitational/teleport/api/types"

	"github.com/jturner-teleport/teleport-usage/internal/exporter"
)

// ---------------------------------------------------------------------------
// fakes
//
// *client.Client is concrete, so the collector's logic is exercised through the
// narrow authPrefGetter seam. The auth preference itself is a REAL
// types.AuthPreferenceV2 built through types.NewAuthPreference, so these tests
// assert against genuine Teleport semantics (legacy second_factor expansion,
// GetWebauthn's NotFound, RequireMFAType defaults) rather than against a
// hand-rolled mock of what we imagine those semantics to be.
// ---------------------------------------------------------------------------

// fakeAuthPrefAPI stands in for the Teleport API client.
type fakeAuthPrefAPI struct {
	pref  types.AuthPreference
	err   error
	calls int
}

func (f *fakeAuthPrefAPI) GetAuthPreference(_ context.Context) (types.AuthPreference, error) {
	f.calls++
	if f.err != nil {
		return nil, f.err
	}
	return f.pref, nil
}

// mustAuthPref builds a validated AuthPreferenceV2, failing the test if the
// spec is one Teleport would reject. Running CheckAndSetDefaults matters: it is
// what turns the legacy `second_factor: otp` on the reference cluster into the
// SecondFactors list the collector reads.
func mustAuthPref(t *testing.T, spec types.AuthPreferenceSpecV2) types.AuthPreference {
	t.Helper()
	pref, err := types.NewAuthPreference(spec)
	if err != nil {
		t.Fatalf("building auth preference: %v", err)
	}
	return pref
}

// ---------------------------------------------------------------------------
// collector metadata
// ---------------------------------------------------------------------------

func TestAuthPrefCollectorMetadata(t *testing.T) {
	c := NewAuthPref(exporter.New("test", "test"))
	if got, want := c.Name(), exporter.CollectorAuthPref; got != want {
		t.Errorf("Name() = %q, want %q", got, want)
	}
	if got, want := c.Interval(), 5*time.Minute; got != want {
		t.Errorf("Interval() = %v, want %v", got, want)
	}
	// Compile-time proof the collector still satisfies the scheduler contract.
	var _ Collector = c
}

// ---------------------------------------------------------------------------
// mapping
// ---------------------------------------------------------------------------

// TestMapsOTPOnlyCluster mirrors the reference cluster exactly:
//
//	second_factor: otp, no webauthn block, no require_session_mfa,
//	no device_trust
//
// This is the honest-but-unflattering posture the exporter exists to surface:
// MFA is on, only OTP is accepted, and nothing enforces it per session.
func TestMapsOTPOnlyCluster(t *testing.T) {
	api := &fakeAuthPrefAPI{pref: mustAuthPref(t, types.AuthPreferenceSpecV2{
		Type:         constants.Local,
		SecondFactor: constants.SecondFactorOTP,
	})}

	got, err := collectAuthPref(context.Background(), api)
	if err != nil {
		t.Fatalf("collectAuthPref() error = %v, want nil", err)
	}

	if !slices.Equal(got.SecondFactors, []string{"otp"}) {
		t.Errorf("SecondFactors = %v, want [otp]", got.SecondFactors)
	}
	if got.WebauthnConfigured {
		t.Error("WebauthnConfigured = true, want false (no webauthn block on the cluster)")
	}
	if got.RequireSessionMFA {
		t.Error("RequireSessionMFA = true, want false (require_session_mfa is unset)")
	}
	if !got.SecondFactorEnforced {
		t.Error("SecondFactorEnforced = false, want true (second_factor: otp is enforced, not optional)")
	}
	if got.DeviceTrustMode != "off" {
		t.Errorf("DeviceTrustMode = %q, want \"off\"", got.DeviceTrustMode)
	}
}

func TestMapsWebauthnCluster(t *testing.T) {
	api := &fakeAuthPrefAPI{pref: mustAuthPref(t, types.AuthPreferenceSpecV2{
		Type: constants.Local,
		SecondFactors: []types.SecondFactorType{
			types.SecondFactorType_SECOND_FACTOR_TYPE_OTP,
			types.SecondFactorType_SECOND_FACTOR_TYPE_WEBAUTHN,
		},
		Webauthn: &types.Webauthn{RPID: "teleport.example.com"},
	})}

	got, err := collectAuthPref(context.Background(), api)
	if err != nil {
		t.Fatalf("collectAuthPref() error = %v, want nil", err)
	}

	if !got.WebauthnConfigured {
		t.Error("WebauthnConfigured = false, want true")
	}
	if !slices.Contains(got.SecondFactors, "webauthn") {
		t.Errorf("SecondFactors = %v, want it to contain \"webauthn\"", got.SecondFactors)
	}
	if !slices.Contains(got.SecondFactors, "otp") {
		t.Errorf("SecondFactors = %v, want it to contain \"otp\"", got.SecondFactors)
	}
}

func TestMapsSSOSecondFactor(t *testing.T) {
	// Teleport refuses an SSO-only second factor while local auth is on (it
	// would lock local users out), so a real SSO-only cluster looks like this.
	api := &fakeAuthPrefAPI{pref: mustAuthPref(t, types.AuthPreferenceSpecV2{
		Type: constants.Local,
		SecondFactors: []types.SecondFactorType{
			types.SecondFactorType_SECOND_FACTOR_TYPE_SSO,
		},
		AllowLocalAuth: types.NewBoolOption(false),
	})}

	got, err := collectAuthPref(context.Background(), api)
	if err != nil {
		t.Fatalf("collectAuthPref() error = %v, want nil", err)
	}
	if !slices.Equal(got.SecondFactors, []string{"sso"}) {
		t.Errorf("SecondFactors = %v, want [sso]", got.SecondFactors)
	}
}

func TestRequireSessionMFAWhenSet(t *testing.T) {
	tests := []struct {
		name string
		mode types.RequireMFAType
		want bool
	}{
		{"off", types.RequireMFAType_OFF, false},
		{"session", types.RequireMFAType_SESSION, true},
		{"session and hardware key", types.RequireMFAType_SESSION_AND_HARDWARE_KEY, true},
		// Hardware-key policies are not "off", and Teleport's own
		// RequireMFAType.IsSessionMFARequired treats them as requiring MFA.
		{"hardware key touch", types.RequireMFAType_HARDWARE_KEY_TOUCH, true},
		{"hardware key pin", types.RequireMFAType_HARDWARE_KEY_PIN, true},
		{"hardware key touch and pin", types.RequireMFAType_HARDWARE_KEY_TOUCH_AND_PIN, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			api := &fakeAuthPrefAPI{pref: mustAuthPref(t, types.AuthPreferenceSpecV2{
				Type:           constants.Local,
				SecondFactor:   constants.SecondFactorOTP,
				RequireMFAType: tt.mode,
			})}

			got, err := collectAuthPref(context.Background(), api)
			if err != nil {
				t.Fatalf("collectAuthPref() error = %v, want nil", err)
			}
			if got.RequireSessionMFA != tt.want {
				t.Errorf("RequireSessionMFA = %v, want %v for %v", got.RequireSessionMFA, tt.want, tt.mode)
			}
		})
	}
}

func TestDeviceTrustModes(t *testing.T) {
	tests := []struct {
		name        string
		deviceTrust *types.DeviceTrust
		want        string
	}{
		// No device_trust block at all: what the reference cluster looks like.
		{"absent", nil, "off"},
		// Present but empty: Teleport calls this the "default" mode. Device
		// trust is Enterprise-only, so on the OSS cluster this exporter watches
		// the effective mode is off.
		{"empty mode", &types.DeviceTrust{}, "off"},
		{"off", &types.DeviceTrust{Mode: constants.DeviceTrustModeOff}, "off"},
		{"optional", &types.DeviceTrust{Mode: constants.DeviceTrustModeOptional}, "optional"},
		{"required", &types.DeviceTrust{Mode: constants.DeviceTrustModeRequired}, "required"},
		// Not in the registry's known set; it must survive as-is rather than be
		// silently rounded down to something weaker.
		{"required for humans", &types.DeviceTrust{Mode: constants.DeviceTrustModeRequiredForHumans}, "required-for-humans"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			api := &fakeAuthPrefAPI{pref: mustAuthPref(t, types.AuthPreferenceSpecV2{
				Type:         constants.Local,
				SecondFactor: constants.SecondFactorOTP,
				DeviceTrust:  tt.deviceTrust,
			})}

			got, err := collectAuthPref(context.Background(), api)
			if err != nil {
				t.Fatalf("collectAuthPref() error = %v, want nil", err)
			}
			if got.DeviceTrustMode != tt.want {
				t.Errorf("DeviceTrustMode = %q, want %q", got.DeviceTrustMode, tt.want)
			}
		})
	}
}

// TestGetWebauthnErrorIsNotACollectorFailure pins the distinction that makes
// this collector useful. GetWebauthn returns NotFound when the cluster has no
// webauthn block — that is not a fault, it IS the finding. Turning it into a
// collector error would withdraw the metrics and hide the very clusters whose
// only OTP is accepted.
func TestGetWebauthnErrorIsNotACollectorFailure(t *testing.T) {
	pref := mustAuthPref(t, types.AuthPreferenceSpecV2{
		Type:         constants.Local,
		SecondFactor: constants.SecondFactorOTP,
	})

	// Confirm the precondition against the real type: GetWebauthn really does
	// error here, so the test is exercising the path it claims to.
	if _, err := pref.GetWebauthn(); err == nil {
		t.Fatal("precondition failed: expected GetWebauthn to error when webauthn is unconfigured")
	}

	got, err := collectAuthPref(context.Background(), &fakeAuthPrefAPI{pref: pref})
	if err != nil {
		t.Fatalf("collectAuthPref() error = %v, want nil (unconfigured webauthn is a valid state)", err)
	}
	if got.WebauthnConfigured {
		t.Error("WebauthnConfigured = true, want false")
	}
	// The rest of the snapshot must still be populated.
	if !slices.Equal(got.SecondFactors, []string{"otp"}) {
		t.Errorf("SecondFactors = %v, want [otp]; the rest of the snapshot must survive", got.SecondFactors)
	}
}

// TestAPIFailureReturnsErrorAndNoSnapshot is the one that matters. If the API
// call fails we know nothing, and "nothing" must not be published as
// second_factor_enforced=0 — that would report a secure cluster as insecure (or
// vice versa) on the strength of a network blip. The scheduler withdraws the
// metrics on a returned error; our job is to return one and publish nothing.
func TestAPIFailureReturnsErrorAndNoSnapshot(t *testing.T) {
	boom := errors.New("connection refused")
	api := &fakeAuthPrefAPI{err: boom}

	got, err := collectAuthPref(context.Background(), api)
	if err == nil {
		t.Fatal("collectAuthPref() error = nil, want non-nil; a failed fetch must not be reported as a posture")
	}
	if !errors.Is(err, boom) {
		t.Errorf("error = %v, want it to wrap %v", err, boom)
	}
	if !reflect.DeepEqual(got, exporter.AuthPref{}) {
		t.Errorf("snapshot = %+v, want the zero value; nothing may be published on failure", got)
	}
}

// TestSecondFactorOffIsReported is the counterpart to the test above. A cluster
// with MFA genuinely disabled is a SUCCESSFUL collection reporting
// SecondFactorEnforced=false. That is a real, publishable finding, and it must
// be distinguishable from "the collector failed" — which is the entire reason
// the failure path returns an error instead of a zero value.
func TestSecondFactorOffIsReported(t *testing.T) {
	api := &fakeAuthPrefAPI{pref: mustAuthPref(t, types.AuthPreferenceSpecV2{
		Type:         constants.Local,
		SecondFactor: constants.SecondFactorOff,
	})}

	got, err := collectAuthPref(context.Background(), api)
	if err != nil {
		t.Fatalf("collectAuthPref() error = %v, want nil; MFA being off is a measurement, not a failure", err)
	}
	if got.SecondFactorEnforced {
		t.Error("SecondFactorEnforced = true, want false")
	}
	if len(got.SecondFactors) != 0 {
		t.Errorf("SecondFactors = %v, want empty", got.SecondFactors)
	}
	if got.WebauthnConfigured {
		t.Error("WebauthnConfigured = true, want false")
	}
}

// TestSecondFactorOptionalIsNotEnforced covers the legacy "optional" setting:
// second factors are available but users may skip them, which is not
// enforcement.
func TestSecondFactorOptionalIsNotEnforced(t *testing.T) {
	api := &fakeAuthPrefAPI{pref: mustAuthPref(t, types.AuthPreferenceSpecV2{
		Type:         constants.Local,
		SecondFactor: constants.SecondFactorOptional,
		Webauthn:     &types.Webauthn{RPID: "teleport.example.com"},
	})}

	got, err := collectAuthPref(context.Background(), api)
	if err != nil {
		t.Fatalf("collectAuthPref() error = %v, want nil", err)
	}
	if got.SecondFactorEnforced {
		t.Error("SecondFactorEnforced = true, want false for second_factor: optional")
	}
	if len(got.SecondFactors) == 0 {
		t.Error("SecondFactors is empty; optional still makes factors available")
	}
}

// TestNilAuthPreferenceIsAFailure guards the other way a nil could slip through
// into a confidently-wrong zero snapshot.
func TestNilAuthPreferenceIsAFailure(t *testing.T) {
	api := &fakeAuthPrefAPI{pref: nil}

	got, err := collectAuthPref(context.Background(), api)
	if err == nil {
		t.Fatal("collectAuthPref() error = nil, want non-nil for a nil auth preference")
	}
	if !reflect.DeepEqual(got, exporter.AuthPref{}) {
		t.Errorf("snapshot = %+v, want the zero value", got)
	}
}

// TestCollectPublishesToRegistry checks the wiring between the mapped snapshot
// and the registry setter, since Collect itself needs a concrete *client.Client
// and cannot be called directly in a unit test.
func TestCollectPublishesToRegistry(t *testing.T) {
	reg := exporter.New("test", "test")
	api := &fakeAuthPrefAPI{pref: mustAuthPref(t, types.AuthPreferenceSpecV2{
		Type:         constants.Local,
		SecondFactor: constants.SecondFactorOTP,
	})}

	c := NewAuthPref(exporter.New("test", "test"))
	c.reg = reg
	if err := c.collectAndPublish(context.Background(), api); err != nil {
		t.Fatalf("collectAndPublish() error = %v, want nil", err)
	}
	if api.calls != 1 {
		t.Errorf("GetAuthPreference called %d times, want 1", api.calls)
	}

	if got := gaugeValue(t, reg, "teleport_usage_auth_second_factor_enforced", nil); got != 1 {
		t.Errorf("second_factor_enforced = %v, want 1", got)
	}
	if got := gaugeValue(t, reg, "teleport_usage_auth_second_factor_enabled", map[string]string{"type": "otp"}); got != 1 {
		t.Errorf("second_factor_enabled{type=otp} = %v, want 1", got)
	}
	if got := gaugeValue(t, reg, "teleport_usage_auth_second_factor_enabled", map[string]string{"type": "webauthn"}); got != 0 {
		t.Errorf("second_factor_enabled{type=webauthn} = %v, want 0", got)
	}
}

// gaugeValue reads one gauge sample out of the registry, failing if it is
// absent — which is how a withdrawn metric shows up.
func gaugeValue(t *testing.T, reg *exporter.Registry, name string, labels map[string]string) float64 {
	t.Helper()

	families, err := reg.Gatherer().Gather()
	if err != nil {
		t.Fatalf("gathering metrics: %v", err)
	}
	for _, fam := range families {
		if fam.GetName() != name {
			continue
		}
		for _, m := range fam.GetMetric() {
			match := true
			for _, lp := range m.GetLabel() {
				if want, ok := labels[lp.GetName()]; ok && want != lp.GetValue() {
					match = false
					break
				}
			}
			if len(m.GetLabel()) != len(labels) {
				match = false
			}
			if match {
				return m.GetGauge().GetValue()
			}
		}
	}
	t.Fatalf("metric %s%v not found in /metrics", name, labels)
	return 0
}

// ---------------------------------------------------------------------------
// live cluster
// ---------------------------------------------------------------------------

// TestLiveAuthPref runs the real collector against a real cluster. It is opt-in
// — skipped unless both env vars are set — because the rest of this file must
// stay hermetic. It exists so the mapping can be checked against a cluster
// rather than only against our own idea of one:
//
//	TELEPORT_USAGE_LIVE_PROXY=teleport.example.com:443 \
//	TELEPORT_USAGE_LIVE_IDENTITY=/path/to/identity \
//	go test ./internal/collect/ -run TestLiveAuthPref -v
//
// The identity file is the same one the deployed exporter uses (tbot writes it
// to the usage-tracker-identity secret), so this exercises the exact code path
// production takes, with production's permissions.
func TestLiveAuthPref(t *testing.T) {
	proxy := os.Getenv("TELEPORT_USAGE_LIVE_PROXY")
	identity := os.Getenv("TELEPORT_USAGE_LIVE_IDENTITY")
	if proxy == "" || identity == "" {
		t.Skip("set TELEPORT_USAGE_LIVE_PROXY and TELEPORT_USAGE_LIVE_IDENTITY to run against a real cluster")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	clt, err := client.New(ctx, client.Config{
		Addrs:       []string{proxy},
		Credentials: []client.Credentials{client.LoadIdentityFile(identity)},
	})
	if err != nil {
		t.Fatalf("connecting to %s: %v", proxy, err)
	}
	defer clt.Close()

	got, err := collectAuthPref(ctx, clt)
	if err != nil {
		t.Fatalf("collectAuthPref() against %s: %v", proxy, err)
	}

	t.Logf("live posture from %s: second_factor_enforced=%v second_factors=%v webauthn_configured=%v require_session_mfa=%v device_trust_mode=%q",
		proxy, got.SecondFactorEnforced, got.SecondFactors, got.WebauthnConfigured, got.RequireSessionMFA, got.DeviceTrustMode)

	// Sanity, not policy: a successful collection must produce a device trust
	// mode, since "" is the value that means "we do not know".
	if got.DeviceTrustMode == "" {
		t.Error("DeviceTrustMode is empty on a successful live collection")
	}
}
