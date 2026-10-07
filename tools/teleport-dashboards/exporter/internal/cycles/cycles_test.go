package cycles

import (
	"testing"
	"time"
)

func TestDaysIn(t *testing.T) {
	cases := []struct {
		year  int
		month time.Month
		want  int
	}{
		{2024, time.February, 29}, // leap year
		{2025, time.February, 28},
		{2025, time.January, 31},
		{2025, time.April, 30},
	}
	for _, c := range cases {
		if got := DaysIn(c.year, c.month); got != c.want {
			t.Errorf("DaysIn(%d, %s) = %d, want %d", c.year, c.month, got, c.want)
		}
	}
}

func TestStartClampsToMonthLength(t *testing.T) {
	// Anchor 31 in February must clamp to the 28th (2025 is not a leap year).
	got := Start(2025, time.February, 31)
	want := time.Date(2025, time.February, 28, 0, 0, 0, 0, time.UTC)
	if !got.Equal(want) {
		t.Errorf("Start(2025, Feb, 31) = %s, want %s", got, want)
	}

	// Anchor within range is used as-is at 00:00 UTC.
	got = Start(2025, time.March, 7)
	want = time.Date(2025, time.March, 7, 0, 0, 0, 0, time.UTC)
	if !got.Equal(want) {
		t.Errorf("Start(2025, Mar, 7) = %s, want %s", got, want)
	}
}

func TestContaining(t *testing.T) {
	anchor := 7
	// 2025-03-10 is in the cycle [2025-03-07, 2025-04-07).
	c := Containing(time.Date(2025, time.March, 10, 12, 0, 0, 0, time.UTC), anchor)
	wantStart := time.Date(2025, time.March, 7, 0, 0, 0, 0, time.UTC)
	wantEnd := time.Date(2025, time.April, 7, 0, 0, 0, 0, time.UTC)
	if !c.Start.Equal(wantStart) || !c.End.Equal(wantEnd) {
		t.Errorf("Containing = [%s, %s), want [%s, %s)", c.Start, c.End, wantStart, wantEnd)
	}

	// A time before the anchor in its month belongs to the previous cycle.
	c = Containing(time.Date(2025, time.March, 3, 0, 0, 0, 0, time.UTC), anchor)
	wantStart = time.Date(2025, time.February, 7, 0, 0, 0, 0, time.UTC)
	wantEnd = time.Date(2025, time.March, 7, 0, 0, 0, 0, time.UTC)
	if !c.Start.Equal(wantStart) || !c.End.Equal(wantEnd) {
		t.Errorf("Containing(pre-anchor) = [%s, %s), want [%s, %s)", c.Start, c.End, wantStart, wantEnd)
	}
}

func TestContainingHalfOpenBoundary(t *testing.T) {
	anchor := 7
	// Exactly at the anchor instant is the start of the new cycle (inclusive).
	at := time.Date(2025, time.March, 7, 0, 0, 0, 0, time.UTC)
	c := Containing(at, anchor)
	if !c.Start.Equal(at) {
		t.Errorf("Containing(anchor instant) start = %s, want %s", c.Start, at)
	}
}

func TestLastN(t *testing.T) {
	anchor := 7
	now := time.Date(2025, time.March, 20, 0, 0, 0, 0, time.UTC)
	got := LastN(now, anchor, 2)
	if len(got) != 3 {
		t.Fatalf("LastN returned %d cycles, want 3", len(got))
	}
	// Oldest-first ordering.
	if !got[0].Start.Before(got[1].Start) || !got[1].Start.Before(got[2].Start) {
		t.Errorf("LastN cycles not oldest-first: %s, %s, %s", got[0].Start, got[1].Start, got[2].Start)
	}
	// Only the last (current) cycle is in progress.
	if got[0].InProgress || got[1].InProgress {
		t.Errorf("older cycles should not be in progress")
	}
	if !got[2].InProgress {
		t.Errorf("current cycle should be in progress")
	}
	// The current cycle must contain now.
	cur := got[2]
	if now.Before(cur.Start) || !now.Before(cur.End) {
		t.Errorf("current cycle [%s, %s) does not contain now %s", cur.Start, cur.End, now)
	}
}
