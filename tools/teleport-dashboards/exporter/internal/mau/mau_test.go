package mau

import "testing"

func TestClassifyUserKind(t *testing.T) {
	cases := []struct {
		name string
		raw  map[string]interface{}
		want UserKindLabel
	}{
		{"missing field", map[string]interface{}{}, UserKindHuman},
		{"nil value", map[string]interface{}{"user_kind": nil}, UserKindHuman},
		{"string bot", map[string]interface{}{"user_kind": "bot"}, UserKindBot},
		{"string human", map[string]interface{}{"user_kind": "human"}, UserKindHuman},
		{"enum string bot", map[string]interface{}{"user_kind": "USER_KIND_BOT"}, UserKindBot},
		{"enum string human", map[string]interface{}{"user_kind": "USER_KIND_HUMAN"}, UserKindHuman},
		{"unknown string", map[string]interface{}{"user_kind": "weird"}, UserKindHuman},
		{"numeric 2 is bot", map[string]interface{}{"user_kind": float64(2)}, UserKindBot},
		{"numeric 1 is human", map[string]interface{}{"user_kind": float64(1)}, UserKindHuman},
		{"numeric 0 is human", map[string]interface{}{"user_kind": float64(0)}, UserKindHuman},
		{"unexpected type", map[string]interface{}{"user_kind": true}, UserKindHuman},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := classifyUserKind(c.raw); got != c.want {
				t.Errorf("classifyUserKind(%v) = %q, want %q", c.raw, got, c.want)
			}
		})
	}
}

func TestSummarizeCountsHumansAndBots(t *testing.T) {
	a := newCycleAccum()
	// human with SSH activity -> ZTA human
	a.ingest(map[string]interface{}{"user": "alice", "user_kind": "human", "event": "session.start"})
	// bot with SSH activity -> counted as MWI bot, not ZTA human
	a.ingest(map[string]interface{}{"user": "bot-ci", "user_kind": "bot", "event": "session.start"})
	// human with an access request -> IG human
	a.ingest(map[string]interface{}{"user": "carol", "user_kind": "human", "event": "access_request.create"})

	s := a.summarize()
	if s.ztaHumanCount != 1 {
		t.Errorf("ztaHumanCount = %d, want 1", s.ztaHumanCount)
	}
	if s.igHumanCount != 1 {
		t.Errorf("igHumanCount = %d, want 1", s.igHumanCount)
	}
	if s.mwiBotCount != 1 {
		t.Errorf("mwiBotCount = %d, want 1", s.mwiBotCount)
	}
}

func TestIngestSuccessfulLoginCount(t *testing.T) {
	a := newCycleAccum()
	a.ingest(map[string]interface{}{"user": "alice", "event": "user.login", "success": true})
	a.ingest(map[string]interface{}{"user": "alice", "event": "user.login", "success": false})
	if a.totalLogins != 1 {
		t.Errorf("totalLogins = %d, want 1 (failed logins excluded)", a.totalLogins)
	}
}
