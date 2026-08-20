// Command transact connects to Postgres using a Teleport Workload
// Identity X.509-SVID as the client certificate, and runs one example
// transaction.
//
// Network path: this process talks to Postgres directly -- PGHOST is
// Postgres' own Kubernetes Service, not anything Teleport proxies. Once
// tbot has written this pod's SVID (see SVID_DIR below), Teleport isn't
// in the connection's network path at all; the SVID alone is what gets
// this client authenticated. (Contrast with the human/CLI path in
// ../../../cli/README.md, which does go through Teleport TCP
// Application Access via `tsh vnet` -- that's a deliberate difference
// this demo draws out, not an inconsistency.)
package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/jackc/pgx/v5"
)

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func mustGetenv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("required environment variable %s is not set", key)
	}
	return v
}

func connect(ctx context.Context, connStr string) (*pgx.Conn, error) {
	retries := 10
	delay := 3 * time.Second

	var lastErr error
	for attempt := 1; attempt <= retries; attempt++ {
		// pgx re-reads the sslcert/sslkey/sslrootcert files on every
		// Connect call, so a long-lived process that reconnects
		// periodically will naturally pick up tbot's rotated SVID
		// without restarting.
		conn, err := pgx.Connect(ctx, connStr)
		if err == nil {
			return conn, nil
		}
		lastErr = err
		log.Printf("[%d/%d] connect failed: %v", attempt, retries, err)
		time.Sleep(delay)
	}
	return nil, fmt.Errorf("could not connect to Postgres: %w", lastErr)
}

func main() {
	svidDir := getenv("SVID_DIR", "/var/run/teleport-wi")
	postgresCA := getenv("POSTGRES_CA", "/etc/postgres-ca/ca.crt")

	// verify-full, not just verify-ca: PGHOST ("postgres") dials the
	// Service directly, and that name is one of the server cert's own
	// SANs (see ../../../../postgres-chart/templates/tls-secrets.yaml)
	// -- so hostname pinning succeeds too, not just the chain-of-trust
	// check.
	connStr := fmt.Sprintf(
		"host=%s port=%s dbname=%s user=%s sslmode=verify-full sslcert=%s sslkey=%s sslrootcert=%s connect_timeout=5",
		mustGetenv("PGHOST"),
		getenv("PGPORT", "5432"),
		getenv("PGDATABASE", "demo"),
		getenv("PGUSER", "app_user"),
		svidDir+"/svid.pem",
		// tbot's `kubernetes_secret` destination names the key file
		// "svid_key.pem", not "svid.key" -- confirmed against a live
		// Secret (that naming is only for the `directory` destination
		// type, which this demo doesn't use).
		svidDir+"/svid_key.pem",
		postgresCA,
	)

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	conn, err := connect(ctx, connStr)
	if err != nil {
		log.Fatal(err)
	}
	defer conn.Close(ctx)

	tx, err := conn.Begin(ctx)
	if err != nil {
		log.Fatalf("begin: %v", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck // no-op once committed

	var id int
	err = tx.QueryRow(ctx,
		`INSERT INTO transactions (account, amount, description)
		 VALUES ($1, $2, $3) RETURNING id`,
		"wi-demo-go", 42.00, "Deposit via Teleport Workload Identity (Go)",
	).Scan(&id)
	if err != nil {
		log.Fatalf("insert: %v", err)
	}

	var account, description string
	var amount float64
	var createdAt time.Time
	err = tx.QueryRow(ctx,
		`SELECT account, amount, description, created_at
		 FROM transactions WHERE id = $1`,
		id,
	).Scan(&account, &amount, &description, &createdAt)
	if err != nil {
		log.Fatalf("select: %v", err)
	}

	if err := tx.Commit(ctx); err != nil {
		log.Fatalf("commit: %v", err)
	}

	fmt.Printf("Inserted and committed transaction #%d: account=%s amount=%.2f description=%q created_at=%s\n",
		id, account, amount, description, createdAt.Format(time.RFC3339))
}
