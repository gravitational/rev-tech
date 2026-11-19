// Package cycles implements Teleport billing-cycle math shared by the mau and
// tpr subcommands. A billing cycle is a half-open window [Start, End) anchored
// to a configurable day-of-month, evaluated in UTC.
package cycles

import (
	"fmt"
	"time"
)

// Bounds is a half-open billing-cycle window [Start, End).
type Bounds struct {
	Start      time.Time
	End        time.Time
	Label      string
	InProgress bool
}

// DaysIn returns the number of days in the given year/month.
func DaysIn(year int, month time.Month) int {
	return time.Date(year, month+1, 0, 0, 0, 0, 0, time.UTC).Day()
}

// Start returns the anchor-day 00:00 UTC for year/month, clamped to the
// last day of the month when anchor exceeds that month's length.
func Start(year int, month time.Month, anchor int) time.Time {
	d := anchor
	if last := DaysIn(year, month); d > last {
		d = last
	}
	return time.Date(year, month, d, 0, 0, 0, 0, time.UTC)
}

// Containing returns the billing cycle whose half-open window contains t.
func Containing(t time.Time, anchor int) Bounds {
	t = t.UTC()
	start := Start(t.Year(), t.Month(), anchor)
	if t.Before(start) {
		prevYear, prevMonth := t.Year(), t.Month()-1
		if prevMonth < 1 {
			prevYear--
			prevMonth = 12
		}
		start = Start(prevYear, prevMonth, anchor)
	}
	nextYear, nextMonth := start.Year(), start.Month()+1
	if nextMonth > 12 {
		nextYear++
		nextMonth = 1
	}
	end := Start(nextYear, nextMonth, anchor)
	return Bounds{
		Start: start,
		End:   end,
		Label: fmt.Sprintf("%s - %s",
			start.Format("2 Jan 2006"),
			end.Add(-24*time.Hour).Format("2 Jan 2006")),
	}
}

// LastN returns the cycle containing now plus n fully-completed preceding
// cycles, oldest-first. The cycle containing now is marked InProgress.
func LastN(now time.Time, anchor, n int) []Bounds {
	current := Containing(now, anchor)
	current.InProgress = true
	out := []Bounds{current}
	for i := 0; i < n; i++ {
		// Pick any instant inside the previous cycle (one day before this start).
		prev := out[len(out)-1].Start.Add(-24 * time.Hour)
		out = append(out, Containing(prev, anchor))
	}
	// Reverse to oldest-first.
	for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
		out[i], out[j] = out[j], out[i]
	}
	return out
}
