#!/usr/bin/env python3
"""Connect to Postgres using a Teleport Workload Identity X.509-SVID as
the client certificate, and run one example transaction.

Network path: this process talks to Postgres directly -- PGHOST is
Postgres' own Kubernetes Service, not anything Teleport proxies. Once
tbot has written this pod's SVID (see SVID_DIR below), Teleport isn't
in the connection's network path at all; the SVID alone is what gets
this client authenticated. (Contrast with the human/CLI path in
../../../cli/README.md, which does go through Teleport TCP Application
Access via `tsh vnet` -- that's a deliberate difference this demo
draws out, not an inconsistency.)

This file is deliberately split into a credential/connection layer
(`connect()`) and a demo payload (`run_demo_transaction()`) so it can
double as a starting point for an AI agent that needs its own
Workload-Identity-authenticated database access -- e.g. a LangChain/MCP
SQL tool, or any agent framework's tool-calling handler. `connect()` is
the part such a tool should reuse as-is; `run_demo_transaction()` is the
part meant to be replaced. See the "AGENT INTEGRATION POINT" comment
below.
"""
import os
import sys
import time

import psycopg

SVID_DIR = os.environ.get("SVID_DIR", "/var/run/teleport-wi")
POSTGRES_CA = os.environ.get("POSTGRES_CA", "/etc/postgres-ca/ca.crt")

PGHOST = os.environ["PGHOST"]
PGPORT = os.environ.get("PGPORT", "5432")
PGDATABASE = os.environ.get("PGDATABASE", "demo")
PGUSER = os.environ.get("PGUSER", "app_user")

CONNECT_RETRIES = int(os.environ.get("CONNECT_RETRIES", "10"))
CONNECT_RETRY_DELAY_SECONDS = float(os.environ.get("CONNECT_RETRY_DELAY_SECONDS", "3"))


def connect() -> psycopg.Connection:
    """Open a Workload-Identity-authenticated connection to Postgres.

    tbot rotates the SVID files under SVID_DIR every renewal_interval
    (see ../../tbot-chart/values.yaml); reading them fresh on each
    connection attempt means a long-lived process never presents an
    expired certificate. libpq validates the SVID's expiry itself, so a
    stale read here would simply fail the handshake, not silently
    succeed with bad credentials.

    An agent embedding this in a longer-lived process (rather than the
    one-shot Job this file runs as) should call `connect()` again
    whenever a query fails with an auth/TLS error, rather than holding
    one connection open indefinitely across SVID rotations.
    """
    # tbot's `kubernetes_secret` destination names the key file
    # "svid_key.pem", not "svid.key" -- confirmed against a live
    # Secret (that naming is only for the `directory` destination type,
    # which this demo doesn't use).
    svid_cert = os.path.join(SVID_DIR, "svid.pem")
    svid_key = os.path.join(SVID_DIR, "svid_key.pem")

    last_err = None
    for attempt in range(1, CONNECT_RETRIES + 1):
        try:
            return psycopg.connect(
                host=PGHOST,
                port=PGPORT,
                dbname=PGDATABASE,
                user=PGUSER,
                # verify-full, not just verify-ca: PGHOST ("postgres")
                # dials the Service directly, and that name is one of
                # the server cert's own SANs (see
                # ../../../../postgres-chart/templates/tls-secrets.yaml)
                # -- so hostname pinning succeeds too, not just the
                # chain-of-trust check.
                sslmode="verify-full",
                sslcert=svid_cert,
                sslkey=svid_key,
                sslrootcert=POSTGRES_CA,
                connect_timeout=5,
            )
        except psycopg.OperationalError as err:
            last_err = err
            print(
                f"[{attempt}/{CONNECT_RETRIES}] connect failed: {err}",
                file=sys.stderr,
            )
            time.sleep(CONNECT_RETRY_DELAY_SECONDS)
    raise SystemExit(f"could not connect to Postgres: {last_err}")


def run_demo_transaction(conn: psycopg.Connection) -> None:
    """The example payload: insert one row, read it back, commit.

    # --- AGENT INTEGRATION POINT -------------------------------------
    # Replace the body of this function with an agent's own database
    # logic -- e.g. a tool handler that takes an LLM-generated SQL
    # statement (or structured query) and executes it against `conn`.
    # `conn` is a normal psycopg3 Connection: reuse it as-is, keep
    # queries parameterized (`%s` placeholders, never f-string SQL, to
    # avoid injection from model-generated input), and keep committing
    # (or rolling back on error) inside a `with conn:` block like below
    # so a failed agent action can't leave a transaction half-applied.
    # -------------------------------------------------------------------
    """
    with conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO transactions (account, amount, description)
                VALUES (%s, %s, %s)
                RETURNING id
                """,
                ("wi-demo-python", 42.00, "Deposit via Teleport Workload Identity (Python)"),
            )
            new_id = cur.fetchone()[0]

            cur.execute(
                """
                SELECT id, account, amount, description, created_at
                FROM transactions WHERE id = %s
                """,
                (new_id,),
            )
            row = cur.fetchone()
            print(f"Inserted and committed transaction: {row}")


def main() -> None:
    conn = connect()
    try:
        run_demo_transaction(conn)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
