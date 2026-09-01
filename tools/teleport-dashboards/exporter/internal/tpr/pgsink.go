package tpr

import (
	"database/sql"
	"fmt"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib" // pure-Go Postgres driver (preserves CGO_ENABLED=0)
)

// pgSink is an optional Postgres mirror of the SQLite snapshot store. It is
// only created when -postgres-dsn is non-empty; when nil, every method is a
// no-op and the program behaves exactly as the SQLite-only path. The Grafana
// dashboard computes billing-cycle peaks from these point-in-time snapshot
// rows, so the tracker only ever writes snapshots here (no cycle aggregation).
type pgSink struct {
	db *sql.DB
}

// newPGSink opens a Postgres connection for the sink. It returns (nil, nil)
// when dsn is empty so callers can treat "no DSN" as "no sink" without special
// casing. A non-empty DSN that fails to connect is a hard error: the sink is
// the whole point when configured.
func newPGSink(dsn string) (*pgSink, error) {
	if dsn == "" {
		return nil, nil
	}
	pdb, err := sql.Open("pgx", dsn)
	if err != nil {
		return nil, fmt.Errorf("opening Postgres connection: %w", err)
	}
	if err := pdb.Ping(); err != nil {
		pdb.Close()
		return nil, fmt.Errorf("pinging Postgres: %w", err)
	}
	return &pgSink{db: pdb}, nil
}

// ensureSchema creates the snapshot tables if they do not already exist.
func (p *pgSink) ensureSchema() error {
	if p == nil {
		return nil
	}
	if _, err := p.db.Exec(`
		CREATE TABLE IF NOT EXISTS public.tpr_history (
			ts timestamptz NOT NULL, total_tpr int, app_tpr int, kube_tpr int, db_tpr int, windows_tpr int, node_tpr int)`); err != nil {
		return fmt.Errorf("creating tpr_history: %w", err)
	}
	if _, err := p.db.Exec(`
		CREATE TABLE IF NOT EXISTS public.mwi_history (
			ts timestamptz NOT NULL, bots int, bot_instances int, spiffe_ids_issued int)`); err != nil {
		return fmt.Errorf("creating mwi_history: %w", err)
	}
	return nil
}

// writeTPR appends one TPR snapshot row, stamped with the current UTC time.
func (p *pgSink) writeTPR(total, app, kube, dbCount, windows, node int) error {
	if p == nil {
		return nil
	}
	_, err := p.db.Exec(
		`INSERT INTO public.tpr_history (ts, total_tpr, app_tpr, kube_tpr, db_tpr, windows_tpr, node_tpr)
		 VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		time.Now().UTC(), total, app, kube, dbCount, windows, node)
	return err
}

// writeMWI appends one MWI snapshot row, stamped with the current UTC time.
func (p *pgSink) writeMWI(bots, botInstances, spiffeIDs int) error {
	if p == nil {
		return nil
	}
	_, err := p.db.Exec(
		`INSERT INTO public.mwi_history (ts, bots, bot_instances, spiffe_ids_issued)
		 VALUES ($1, $2, $3, $4)`,
		time.Now().UTC(), bots, botInstances, spiffeIDs)
	return err
}

// trim removes snapshot rows older than the given number of days, mirroring
// the SQLite retention cleanup.
func (p *pgSink) trim(days int) error {
	if p == nil {
		return nil
	}
	if _, err := p.db.Exec(
		`DELETE FROM public.tpr_history WHERE ts < now() - make_interval(days => $1)`, days); err != nil {
		return fmt.Errorf("trimming tpr_history: %w", err)
	}
	if _, err := p.db.Exec(
		`DELETE FROM public.mwi_history WHERE ts < now() - make_interval(days => $1)`, days); err != nil {
		return fmt.Errorf("trimming mwi_history: %w", err)
	}
	return nil
}

// close releases the underlying connection pool.
func (p *pgSink) close() error {
	if p == nil {
		return nil
	}
	return p.db.Close()
}
