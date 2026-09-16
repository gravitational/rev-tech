package tpr

import (
	"database/sql"
	"testing"
	"time"

	_ "modernc.org/sqlite"

	"github.com/jturner-teleport/teleport-usage/internal/cycles"
)

// newTestTracker returns a tracker backed by an in-memory SQLite database with
// the same schema initDatabase creates. It does not call initDatabase (which
// opens a file-backed db); instead it creates the tables directly so the test
// is self-contained and leaves no artifacts on disk.
func newTestTracker(t *testing.T) *tracker {
	t.Helper()
	db, err := sql.Open("sqlite", ":memory:")
	if err != nil {
		t.Fatalf("open in-memory sqlite: %v", err)
	}
	t.Cleanup(func() { db.Close() })

	schema := []string{
		`CREATE TABLE tpr_data (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			timestamp TEXT,
			total_tpr INTEGER,
			app_tpr INTEGER,
			kube_tpr INTEGER,
			db_tpr INTEGER,
			windows_tpr INTEGER,
			node_tpr INTEGER
		)`,
		`CREATE TABLE mwi_data (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			timestamp TEXT,
			bots INTEGER,
			bot_instances INTEGER,
			spiffe_ids_issued INTEGER
		)`,
	}
	for _, stmt := range schema {
		if _, err := db.Exec(stmt); err != nil {
			t.Fatalf("create schema: %v", err)
		}
	}

	return &tracker{db: db}
}

const tsLayout = "2006-01-02 15:04:05"

func insertTPR(t *testing.T, db *sql.DB, ts time.Time, total, app, kube, dbc, win, node int) {
	t.Helper()
	_, err := db.Exec(
		`INSERT INTO tpr_data (timestamp, total_tpr, app_tpr, kube_tpr, db_tpr, windows_tpr, node_tpr)
		 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		ts.Format(tsLayout), total, app, kube, dbc, win, node)
	if err != nil {
		t.Fatalf("insert tpr_data: %v", err)
	}
}

func insertMWI(t *testing.T, db *sql.DB, ts time.Time, bots, inst, spiffe int) {
	t.Helper()
	_, err := db.Exec(
		`INSERT INTO mwi_data (timestamp, bots, bot_instances, spiffe_ids_issued)
		 VALUES (?, ?, ?, ?)`,
		ts.Format(tsLayout), bots, inst, spiffe)
	if err != nil {
		t.Fatalf("insert mwi_data: %v", err)
	}
}

// TestAggregateCycleNoRows verifies that a cycle window with no snapshot rows
// yields the nil "n/a" sentinel (not 0) and reports the data as unavailable.
func TestAggregateCycleNoRows(t *testing.T) {
	tr := newTestTracker(t)

	start := time.Date(2026, 5, 1, 0, 0, 0, 0, time.UTC)
	c := cycles.Bounds{
		Start: start,
		End:   start.AddDate(0, 1, 0),
		Label: "empty-cycle",
	}

	row := tr.aggregateCycle(c)

	if row["tpr_available"].(bool) {
		t.Errorf("tpr_available = true, want false for an empty cycle")
	}
	if row["mwi_available"].(bool) {
		t.Errorf("mwi_available = true, want false for an empty cycle")
	}

	// Every numeric cell must be the nil sentinel, never 0.
	for _, key := range []string{
		"total_tpr", "applications", "kubernetes", "databases",
		"windows_desktops", "nodes", "bots", "bot_instances", "spiffe_ids_issued",
	} {
		if v := row[key]; v != nil {
			t.Errorf("%s = %#v, want nil for an empty cycle", key, v)
		}
	}
}

// TestAggregateCycleWithRows verifies that a cycle with multiple snapshots
// returns the MAX (peak) for TPR/MWI counts and the SUM for SPIFFE issuance,
// and that rows outside the window are excluded.
func TestAggregateCycleWithRows(t *testing.T) {
	tr := newTestTracker(t)

	start := time.Date(2026, 5, 1, 0, 0, 0, 0, time.UTC)
	c := cycles.Bounds{
		Start: start,
		End:   start.AddDate(0, 1, 0), // 2026-06-01
		Label: "may-2026",
	}

	// Two snapshots inside the window: counts should take the peak (MAX),
	// SPIFFE issuance should accumulate (SUM).
	insertTPR(t, tr.db, start.AddDate(0, 0, 2), 10, 4, 3, 2, 1, 0)
	insertTPR(t, tr.db, start.AddDate(0, 0, 9), 7, 2, 5, 1, 0, 3) // kube + node peak here
	insertMWI(t, tr.db, start.AddDate(0, 0, 2), 5, 5, 2)
	insertMWI(t, tr.db, start.AddDate(0, 0, 9), 8, 8, 4) // bots/inst peak here

	// Rows OUTSIDE the window must be ignored (End is exclusive).
	insertTPR(t, tr.db, c.End, 999, 999, 999, 999, 999, 999)
	insertMWI(t, tr.db, start.AddDate(0, 0, -1), 999, 999, 999)

	row := tr.aggregateCycle(c)

	if !row["tpr_available"].(bool) {
		t.Fatalf("tpr_available = false, want true")
	}
	if !row["mwi_available"].(bool) {
		t.Fatalf("mwi_available = false, want true")
	}

	wantInt := map[string]int{
		"total_tpr":         10, // MAX(10,7)
		"applications":      4,  // MAX(4,2)
		"kubernetes":        5,  // MAX(3,5)
		"databases":         2,  // MAX(2,1)
		"windows_desktops":  1,  // MAX(1,0)
		"nodes":             3,  // MAX(0,3)
		"bots":              8,  // MAX(5,8)
		"bot_instances":     8,  // MAX(5,8)
		"spiffe_ids_issued": 6,  // SUM(2,4)
	}
	for key, want := range wantInt {
		got, ok := row[key].(int)
		if !ok {
			t.Errorf("%s = %#v, want int %d", key, row[key], want)
			continue
		}
		if got != want {
			t.Errorf("%s = %d, want %d", key, got, want)
		}
	}
}
