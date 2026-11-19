// Command teleport-usage is a single binary that unifies the two rev-tech
// Teleport usage trackers as subcommands:
//
//	teleport-usage mau ...   one-shot Monthly Active Users report
//	teleport-usage tpr ...   long-lived Teleport Protected Resources tracker
//
// For backwards compatibility with the legacy teleport-mau-tracker /
// teleport-tpr-tracker binaries, the subcommand is also inferred from argv[0]:
// invoking the binary via a symlink whose name contains "mau" or "tpr" selects
// that subcommand directly (so the original flags work unchanged).
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"log/slog"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/gravitational/teleport/api"

	"github.com/jturner-teleport/teleport-usage/internal/collect"
	"github.com/jturner-teleport/teleport-usage/internal/exporter"
	"github.com/jturner-teleport/teleport-usage/internal/mau"
	"github.com/jturner-teleport/teleport-usage/internal/teleportclient"
	"github.com/jturner-teleport/teleport-usage/internal/tpr"
)

// buildVersion is stamped at build time with -ldflags "-X main.buildVersion=...".
var buildVersion = "dev"

func main() {
	sub, args := resolveSubcommand()

	switch sub {
	case "mau":
		runMAU(args)
	case "tpr":
		runTPR(args)
	case "exporter":
		runExporter(args)
	default:
		usage()
		os.Exit(2)
	}
}

// resolveSubcommand determines the effective subcommand and the args to pass to
// it. argv[0] aliasing takes precedence (legacy symlink names); otherwise the
// first positional arg selects the subcommand.
func resolveSubcommand() (string, []string) {
	base := filepath.Base(os.Args[0])
	switch {
	case strings.Contains(base, "mau"):
		return "mau", os.Args[1:]
	case strings.Contains(base, "tpr"):
		return "tpr", os.Args[1:]
	}
	if len(os.Args) < 2 {
		return "", nil
	}
	return os.Args[1], os.Args[2:]
}

func usage() {
	fmt.Fprintf(os.Stderr, `teleport-usage: Teleport usage and billing reporting

Usage:
  teleport-usage <command> [flags]

Commands:
  mau        One-shot Monthly Active Users report (ZTA + IG) over recent audit events.
  tpr        Long-lived Teleport Protected Resources & MWI tracker.
  exporter   Long-lived Prometheus exporter for usage and posture metrics.

Run "teleport-usage <command> -h" for command-specific flags.

The legacy binary names teleport-mau-tracker / teleport-tpr-tracker are also
supported: invoking via a symlink named for a command selects it automatically.
`)
}

func runMAU(args []string) {
	o := mau.DefaultOptions()
	fs := flag.NewFlagSet("mau", flag.ExitOnError)

	fs.StringVar(&o.ProxyAddr, "proxy", "",
		"Teleport proxy address, e.g. teleport.example.com:443 (required)")
	fs.StringVar(&o.IdentityFile, "identity_file", "",
		"Path to Teleport identity file (optional - enables use of an identity file instead of ambient tsh credentials)")
	fs.StringVar(&o.Format, "format", "text",
		"Output file type - text or json")
	fs.IntVar(&o.BillingDay, "billing-day", 0,
		"Billing cycle anchor day (1-31). When set, the report is aligned to Teleport billing cycles instead of a rolling daysBack window.")
	fs.IntVar(&o.Cycles, "cycles", 3,
		"Number of completed cycles to include alongside the in-progress cycle (only used with -billing-day).")

	_ = fs.Parse(args)

	if err := mau.Run(context.Background(), o); err != nil {
		log.Fatalf("%v", err)
	}
}

func runTPR(args []string) {
	o := tpr.DefaultOptions()
	fs := flag.NewFlagSet("tpr", flag.ExitOnError)

	fs.StringVar(&o.ProxyAddr, "proxy", "",
		"Teleport proxy address, e.g. teleport.example.com:443 (required)")
	fs.StringVar(&o.Format, "format", "text",
		"Output file type - text or json")
	fs.StringVar(&o.IdentityFile, "identity_file", "",
		"Path to Teleport identity file (optional - enables use of an identity file instead of ambient tsh credentials)")
	fs.IntVar(&o.BillingDay, "billing-day", 0,
		"Billing cycle anchor day (1-31). When set, an additional per-cycle history section is included in each report.")
	fs.IntVar(&o.Cycles, "cycles", 3,
		"Number of completed cycles to include alongside the in-progress cycle (only used with -billing-day).")
	fs.StringVar(&o.PostgresDSN, "postgres-dsn", "",
		"Optional Postgres DSN. When set, snapshot rows are also written to public.tpr_history / public.mwi_history alongside the SQLite store. Empty (default) = SQLite only.")

	_ = fs.Parse(args)

	if err := tpr.Run(context.Background(), o); err != nil {
		log.Fatalf("%v", err)
	}
}

// --- exporter subcommand -----------------------------------------------------

// envOr returns the environment override for a flag default. Config precedence
// is flag > env > default, which is what a container deployment needs: the
// image sets no flags and everything comes from the pod spec.
func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envDurationOr(key string, def time.Duration) time.Duration {
	if v := os.Getenv(key); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			return d
		}
		log.Printf("[WARN] ignoring unparseable %s=%q", key, v)
	}
	return def
}

func runExporter(args []string) {
	fs := flag.NewFlagSet("exporter", flag.ExitOnError)

	proxy := fs.String("proxy", envOr("TELEPORT_USAGE_PROXY", ""),
		"Teleport proxy address, e.g. teleport.example.com:443 (required) [$TELEPORT_USAGE_PROXY]")
	identityFile := fs.String("identity-file", envOr("TELEPORT_USAGE_IDENTITY_FILE", ""),
		"Path to a Teleport identity file. Empty uses the ambient tsh profile. [$TELEPORT_USAGE_IDENTITY_FILE]")
	metricsAddr := fs.String("metrics-addr", envOr("TELEPORT_USAGE_METRICS_ADDR", ":8080"),
		"Address for /metrics, /healthz and /readyz [$TELEPORT_USAGE_METRICS_ADDR]")
	pingTimeout := fs.Duration("ping-timeout", envDurationOr("TELEPORT_USAGE_PING_TIMEOUT", 30*time.Second),
		"Timeout for the startup version check [$TELEPORT_USAGE_PING_TIMEOUT]")

	_ = fs.Parse(args)

	if *proxy == "" {
		log.Fatalf("-proxy is required (or set TELEPORT_USAGE_PROXY)")
	}

	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelInfo})))

	reg := exporter.New(buildVersion, api.Version)
	provider := teleportclient.NewProvider(*proxy, *identityFile)
	defer func() { _ = provider.Close() }()

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	srv := exporter.NewServer(reg)
	errCh := make(chan error, 2)

	// Serve before anything that talks to Teleport. The version check dials the
	// proxy, and a proxy that accepts the connection but never answers would
	// otherwise keep /healthz unavailable for the whole ping timeout -- long
	// enough for a Kubernetes liveness probe to kill a pod that is working
	// exactly as designed.
	go func() { errCh <- srv.ListenAndServe(ctx, *metricsAddr) }()

	// Startup version check. Advisory, not fatal: refusing to start on skew
	// would take monitoring down exactly when a cluster is mid-upgrade, which
	// is when it is most wanted. It is surfaced as a metric instead.
	//
	// It matters because Teleport adds resource kinds in MINOR releases, so a
	// binary built against an older minor silently under-counts a newer
	// cluster -- an under-count published as fact, which is the failure class
	// this exporter exists to eliminate.
	checkVersion(ctx, provider, reg, *pingTimeout)

	sched := collect.NewScheduler(reg, provider,
		collect.NewResources(reg),
		collect.NewMWI(reg),
		collect.NewAuthPref(reg),
	)
	go func() { errCh <- sched.Run(ctx) }()

	if err := <-errCh; err != nil {
		log.Fatalf("exporter: %v", err)
	}
	slog.Info("exporter stopped")
}

// checkVersion pings the cluster to record build info and detect version skew.
// A failure here is logged and left to the collectors to report; the exporter
// still starts, because /readyz will stay 503 until something succeeds.
func checkVersion(ctx context.Context, provider *teleportclient.Provider, reg *exporter.Registry, timeout time.Duration) {
	pingCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	clt, err := provider.Client(pingCtx)
	if err != nil {
		slog.Error("startup connection failed; collectors will retry", "error", err)
		reg.SetBuildInfo(buildVersion, api.Version, "")
		return
	}

	pong, err := clt.Ping(pingCtx)
	if err != nil {
		slog.Error("startup ping failed; collectors will retry", "error", err)
		reg.SetBuildInfo(buildVersion, api.Version, "")
		return
	}

	reg.SetBuildInfo(buildVersion, api.Version, pong.ClusterName)

	mismatch := majorMinor(pong.ServerVersion) != majorMinor(api.Version)
	reg.SetVersionMismatch(mismatch)
	if mismatch {
		slog.Warn("Teleport version skew: this binary was built against a different minor release. "+
			"New resource kinds land in minor releases, so counts may be low. "+
			"Rebuild with `make build-for TELEPORT_VERSION=v<server version>`.",
			"server_version", pong.ServerVersion, "client_api_version", api.Version)
	} else {
		slog.Info("connected", "cluster", pong.ClusterName, "server_version", pong.ServerVersion)
	}
}

// majorMinor reduces a semver string to "MAJOR.MINOR", ignoring patch and any
// pre-release suffix. Patch differences do not change the resource surface.
func majorMinor(v string) string {
	v = strings.TrimPrefix(v, "v")
	parts := strings.SplitN(v, ".", 3)
	if len(parts) < 2 {
		return v
	}
	return parts[0] + "." + parts[1]
}
