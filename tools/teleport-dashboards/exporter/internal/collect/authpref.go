package collect

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/gravitational/teleport/api/client"
	"github.com/gravitational/teleport/api/constants"
	"github.com/gravitational/teleport/api/types"

	"github.com/jturner-teleport/teleport-usage/internal/exporter"
)

// authPrefInterval is deliberately slow. Cluster auth preference is changed by
// hand, perhaps a few times in a cluster's life; polling it harder buys nothing
// and costs an API round trip.
const authPrefInterval = 5 * time.Minute

// authPrefGetter is the slice of the Teleport API this collector needs.
// *client.Client is a concrete type with no interface of its own, so this
// narrow seam is what makes the mapping testable without a live cluster.
type authPrefGetter interface {
	GetAuthPreference(ctx context.Context) (types.AuthPreference, error)
}

// AuthPrefCollector reports the cluster-wide MFA and device-trust posture.
//
// This is the signal no Grafana datasource can produce. The audit log records
// an auth_preference.update event when the setting changes, but the event body
// carries only admin_actions_mfa_changed: 1 — a flag saying "something moved",
// not the value it moved to. Postgres and the audit log therefore cannot answer
// "is a second factor required, and is it phishing-resistant?" at all. Only the
// API can, and that is the whole reason this exporter exists.
//
// It is layer 1 of the MFA picture. The dashboards can already show layer 2
// (which users have enrolled a device) and layer 3 (which roles set
// require_session_mfa). Without layer 1 those two are ungrounded: 100% device
// enrollment means very little if the cluster only accepts TOTP, and roles
// requiring session MFA mean nothing if no role is assigned. On the reference
// cluster all three layers together read "MFA is on, OTP-only, and enforced by
// nothing" — a statement no existing panel can make.
type AuthPrefCollector struct {
	reg *exporter.Registry
}

// NewAuthPref builds the collector bound to the registry it publishes into.
//
// The registry is a required argument, matching NewResources and NewMWI. An
// earlier version allowed a nil registry "for tests", which made it possible to
// wire a collector that returns success while publishing nothing -- precisely
// the failure this exporter exists to eliminate, reintroduced as an API
// affordance. Tests exercise the unexported collectAuthPref directly instead.
func NewAuthPref(reg *exporter.Registry) *AuthPrefCollector {
	if reg == nil {
		panic("collect.NewAuthPref: registry must not be nil")
	}
	return &AuthPrefCollector{reg: reg}
}

// Name implements Collector.
func (c *AuthPrefCollector) Name() string { return exporter.CollectorAuthPref }

// Interval implements Collector.
func (c *AuthPrefCollector) Interval() time.Duration { return authPrefInterval }

// Collect implements Collector. It takes the concrete *client.Client the
// scheduler hands out and defers to collectAndPublish for everything testable.
func (c *AuthPrefCollector) Collect(ctx context.Context, clt *client.Client) error {
	return c.collectAndPublish(ctx, clt)
}

// collectAndPublish maps the posture and publishes it. It publishes ONLY on
// success: any error returns before SetAuthPref is reached, so the scheduler's
// MarkFailure withdraws the metrics and the panel reads "No data".
func (c *AuthPrefCollector) collectAndPublish(ctx context.Context, api authPrefGetter) error {
	snapshot, err := collectAuthPref(ctx, api)
	if err != nil {
		return err
	}
	c.reg.SetAuthPref(snapshot)
	return nil
}

// collectAuthPref maps types.AuthPreference onto exporter.AuthPref.
//
// On any failure it returns the ZERO snapshot together with a non-nil error,
// and the caller must publish neither. This is not defensive tidiness: a
// zero-valued AuthPref says second_factor_enforced=0, webauthn_configured=0,
// require_session_mfa=0 — i.e. "this cluster has no MFA whatsoever". Publishing
// that because an API call timed out would be a security-relevant lie, and it
// is indistinguishable on a dashboard from a cluster that really is wide open.
// Withdrawing the metrics instead makes the difference visible: a genuinely
// unprotected cluster reports 0, an unmeasurable one reports nothing.
func collectAuthPref(ctx context.Context, api authPrefGetter) (exporter.AuthPref, error) {
	pref, err := api.GetAuthPreference(ctx)
	if err != nil {
		return exporter.AuthPref{}, fmt.Errorf("getting cluster auth preference: %w", err)
	}
	if pref == nil {
		// A nil preference with a nil error would otherwise panic below, or
		// worse, be mapped into a confident all-zeros posture.
		return exporter.AuthPref{}, fmt.Errorf("getting cluster auth preference: got a nil auth preference")
	}

	factors := pref.GetSecondFactors()
	labels := make([]string, 0, len(factors))
	for _, f := range factors {
		if label := secondFactorLabel(f); label != "" {
			labels = append(labels, label)
		}
	}

	return exporter.AuthPref{
		// IsSecondFactorEnforced is true when at least one factor is available
		// AND the legacy setting is not "optional" (available but skippable).
		// "Available" and "enforced" are different claims and the dashboard
		// makes the enforced one.
		SecondFactorEnforced: pref.IsSecondFactorEnforced(),
		SecondFactors:        labels,
		WebauthnConfigured:   webauthnConfigured(pref),
		// Teleport's own helper: any RequireMFAType other than OFF requires
		// per-session MFA. The hardware-key variants count, since they are
		// stricter than plain session MFA rather than an alternative to it.
		RequireSessionMFA: pref.GetRequireMFAType().IsSessionMFARequired(),
		DeviceTrustMode:   deviceTrustMode(pref.GetDeviceTrust()),
	}, nil
}

// webauthnConfigured reports whether the cluster has a webauthn block.
//
// GetWebauthn returns NotFound when Spec.Webauthn is nil. That is a
// configuration fact, not a fetch failure — the cluster we are watching is
// exactly such a cluster — so it maps to false and the collection succeeds.
// Escalating it to a collector error would withdraw the metrics and hide every
// cluster accepting only OTP, which is the opposite of the point.
func webauthnConfigured(pref types.AuthPreference) bool {
	wa, err := pref.GetWebauthn()
	return err == nil && wa != nil
}

// secondFactorLabel maps the protobuf enum to the lowercase label the registry
// expects. It cannot use String(): that yields "SECOND_FACTOR_TYPE_OTP".
func secondFactorLabel(f types.SecondFactorType) string {
	switch f {
	case types.SecondFactorType_SECOND_FACTOR_TYPE_OTP:
		return "otp"
	case types.SecondFactorType_SECOND_FACTOR_TYPE_WEBAUTHN:
		return "webauthn"
	case types.SecondFactorType_SECOND_FACTOR_TYPE_SSO:
		return "sso"
	case types.SecondFactorType_SECOND_FACTOR_TYPE_UNSPECIFIED:
		return ""
	default:
		// A factor type added by a newer Teleport. Derive a label rather than
		// drop it: the registry exports unknown types verbatim, and silently
		// discarding a second factor would under-report the cluster's posture.
		return strings.ToLower(strings.TrimPrefix(f.String(), "SECOND_FACTOR_TYPE_"))
	}
}

// deviceTrustMode normalises the device trust mode.
//
// The block is absent on clusters that never configured it, and an explicitly
// present but empty Mode is what Teleport calls the "default" mode. That
// default is "off" for OSS and "optional" for Enterprise; device trust is an
// Enterprise feature and this exporter runs against OSS, so unset maps to
// "off". Modes we do not recognise (e.g. "required-for-humans") pass through
// untouched — the registry emits them as their own series, and rounding an
// unfamiliar mode down to a weaker known one would overstate the risk.
func deviceTrustMode(dt *types.DeviceTrust) string {
	if dt == nil || dt.Mode == "" {
		return constants.DeviceTrustModeOff
	}
	return dt.Mode
}
