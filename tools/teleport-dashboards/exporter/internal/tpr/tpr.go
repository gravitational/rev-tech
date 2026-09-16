// Package tpr implements the long-lived Teleport Protected Resources tracker:
// it polls the cluster for resource and Machine & Workload Identity counts,
// persists rolling snapshots to SQLite (and optionally Postgres), and re-emits
// a text or JSON report each interval.
package tpr

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/gravitational/teleport/api/client"
	machineidv1pb "github.com/gravitational/teleport/api/gen/proto/go/teleport/machineid/v1"
	"github.com/gravitational/teleport/api/types"
	_ "modernc.org/sqlite"

	"github.com/jturner-teleport/teleport-usage/internal/cycles"
	"github.com/jturner-teleport/teleport-usage/internal/preflight"
	"github.com/jturner-teleport/teleport-usage/internal/teleportclient"
)

// Options carries the resolved configuration for a tpr run. Flag-derived values
// that were package-level vars in the original program now live here.
type Options struct {
	// ProxyAddr is the Teleport proxy address (required; e.g. host:443).
	ProxyAddr string
	// IdentityFile, when non-empty, authenticates with an exported identity
	// file instead of the ambient tsh profile.
	IdentityFile string
	// Format is "text" or "json".
	Format string
	// BillingDay is the billing-cycle anchor day (1-31), or 0 to disable the
	// per-cycle history section.
	BillingDay int
	// Cycles is the number of completed cycles to include alongside the
	// in-progress cycle (only used with BillingDay).
	Cycles int
	// PostgresDSN, when non-empty, enables the Postgres snapshot sink.
	PostgresDSN string

	// UpdateInterval is how often TPR data is refreshed.
	UpdateInterval time.Duration
	// DataRetentionDays is how many days of historical data to keep.
	DataRetentionDays int
	// EventBatchSize is the number of events to fetch per SearchEvents page for
	// instance.join/bot.join monitoring.
	EventBatchSize int
}

// DefaultOptions returns Options populated with the original program's tunable
// defaults (updateInterval, dataRetentionDays, eventBatchSize).
func DefaultOptions() Options {
	return Options{
		Format:            "text",
		Cycles:            3,
		UpdateInterval:    1 * time.Hour,
		DataRetentionDays: 30,
		EventBatchSize:    5000,
	}
}

// Resource represents a tracked Teleport Protected Resource (TPR).
// More info: https://goteleport.com/docs/usage-billing/#teleport-protected-resources
type Resource struct {
	Name       string
	Kind       string
	Static     bool
	LastSeen   time.Time
	InstanceID string
}

// MWIUsage represents Machine & Workload Identity (MWI) usage tracking
type MWIUsage struct {
	Bots            int // Configured Machine ID bots (current state, via ListBots)
	BotInstances    int // Active bot instances (current state, via ListBotInstances)
	SpiffeIDsIssued int // SPIFFE IDs issued in the period (counted from spiffe_svid.issue events)
}

// tracker holds the runtime state of a single tpr run. It replaces the
// package-level globals from the original program so the package no longer
// relies on cross-file mutable state.
type tracker struct {
	opt Options

	resources      map[string]Resource // In-memory map to track active resources (TPR)
	mwiMetrics     MWIUsage            // MWI usage metrics
	resourcesMutex sync.Mutex          // Mutex to ensure safe concurrent access
	db             *sql.DB             // SQLite database connection
	pg             *pgSink             // Optional Postgres sink (nil when -postgres-dsn is empty)
}

// Run starts the long-lived TPR tracker described by o. It performs preflight
// checks, connects to Teleport, initializes the SQLite store and optional
// Postgres sink, then loops forever refreshing data and writing reports. It
// mirrors the original teleport-tpr-tracker behavior and only returns on a
// fatal setup error.
func Run(ctx context.Context, o Options) error {
	if o.ProxyAddr == "" {
		return fmt.Errorf("-proxy is required (e.g. -proxy teleport.example.com:443). Run with -h for usage.")
	}
	canonicalProxy, err := preflight.Proxy(o.ProxyAddr)
	if err != nil {
		return err
	}
	o.ProxyAddr = canonicalProxy

	o.Format = strings.ToLower(strings.TrimSpace(o.Format))
	if o.Format != "text" && o.Format != "json" {
		return fmt.Errorf("invalid -format %q (expected text or json)", o.Format)
	}

	if o.IdentityFile != "" {
		if _, err := os.Stat(o.IdentityFile); err != nil {
			return fmt.Errorf("identity file not accessible: %w", err)
		}
	} else {
		if err := preflight.TshProfile(o.ProxyAddr); err != nil {
			return err
		}
	}

	if o.BillingDay < 0 || o.BillingDay > 31 {
		return fmt.Errorf("invalid -billing-day %d (expected 1-31, or 0 to disable)", o.BillingDay)
	}
	if o.Cycles < 0 {
		return fmt.Errorf("invalid -cycles %d (must be >= 0)", o.Cycles)
	}
	if o.BillingDay > 0 {
		oldest := cycles.LastN(time.Now().UTC(), o.BillingDay, o.Cycles)[0].Start
		spanDays := int(time.Since(oldest).Hours() / 24)
		if spanDays > o.DataRetentionDays {
			log.Printf("[WARN] Requested -cycles=%d spans ~%d days but dataRetentionDays=%d; older cycles will be empty until SQLite history catches up.",
				o.Cycles, spanDays, o.DataRetentionDays)
		}
	}

	t := &tracker{
		opt:       o,
		resources: make(map[string]Resource),
	}

	if err := t.initDatabase(); err != nil {
		return err
	}
	defer t.db.Close()

	// Optional Postgres sink. When -postgres-dsn is empty, pg stays nil and the
	// program behaves exactly as the SQLite-only path. When set, a failure to
	// connect is fatal — the sink is the whole point when configured.
	t.pg, err = newPGSink(o.PostgresDSN)
	if err != nil {
		return fmt.Errorf("Failed to connect to Postgres sink: %w", err)
	}
	if t.pg != nil {
		defer t.pg.close()
		if err := t.pg.ensureSchema(); err != nil {
			return fmt.Errorf("Failed to initialize Postgres schema: %w", err)
		}
		if err := t.pg.trim(o.DataRetentionDays); err != nil {
			log.Printf("[ERROR] Failed to trim old Postgres records: %v", err)
		}
		log.Println("[INFO] Postgres sink enabled (public.tpr_history / public.mwi_history)")
	}

	clt, err := teleportclient.Connect(ctx, o.ProxyAddr, o.IdentityFile)
	if err != nil {
		return fmt.Errorf("Failed to create client: %w", err)
	}
	defer clt.Close()

	log.Println("[INFO] Teleport Resource Tracker is running...")

	// Initial data collection & report generation
	t.fetchAllResources(ctx, clt)
	t.fetchMWI(ctx, clt)
	t.monitorEvents(ctx, clt)
	t.updateMetrics()
	t.writeReportsToFile()

	// Start periodic updates based on configured interval
	go func() {
		time.Sleep(o.UpdateInterval)

		for {
			t.fetchAllResources(ctx, clt)
			t.fetchMWI(ctx, clt)
			t.monitorEvents(ctx, clt)
			t.updateMetrics()
			t.writeReportsToFile()
			t.cleanupStaleResources()
			if err := t.pg.trim(o.DataRetentionDays); err != nil {
				log.Printf("[ERROR] Failed to trim old Postgres records: %v", err)
			}
			time.Sleep(o.UpdateInterval)
		}
	}()

	select {} // Keeps the program running indefinitely until process is killed
}

// initDatabase creates an SQLite database file for storing TPR and MWI data.
// Also removes old data based on configured retention period to protect against storage bloat.
func (t *tracker) initDatabase() error {
	var err error
	t.db, err = sql.Open("sqlite", "teleport_usage_data.db")
	if err != nil {
		return fmt.Errorf("Failed to open database: %w", err)
	}

	// Create TPR table
	_, err = t.db.Exec(`
	CREATE TABLE IF NOT EXISTS tpr_data (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		timestamp TEXT,
		total_tpr INTEGER,
		app_tpr INTEGER,
		kube_tpr INTEGER,
		db_tpr INTEGER,
		windows_tpr INTEGER,
		node_tpr INTEGER
		)
	`)
	if err != nil {
		return fmt.Errorf("Failed to create TPR table: %w", err)
	}

	// Create MWI table
	_, err = t.db.Exec(`
	CREATE TABLE IF NOT EXISTS mwi_data (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		timestamp TEXT,
		bots INTEGER,
		bot_instances INTEGER,
		spiffe_ids_issued INTEGER
		)
	`)
	if err != nil {
		return fmt.Errorf("Failed to create MWI table: %w", err)
	}

	// Cleanup old records based on configured retention period
	_, err = t.db.Exec(fmt.Sprintf(`DELETE FROM tpr_data WHERE timestamp < datetime('now', '-%d days')`, t.opt.DataRetentionDays))
	if err != nil {
		log.Printf("[ERROR] Failed to clean up old TPR records: %v", err)
	}

	_, err = t.db.Exec(fmt.Sprintf(`DELETE FROM mwi_data WHERE timestamp < datetime('now', '-%d days')`, t.opt.DataRetentionDays))
	if err != nil {
		log.Printf("[ERROR] Failed to clean up old MWI records: %v", err)
	}

	return nil
}

// monitorEvents watches for instance.join and spiffe_svid.issue events to detect new resources and SPIFFE issuance. (Bot/bot-instance counts come from fetchMWI's current-state listing, not join events.)
func (t *tracker) monitorEvents(ctx context.Context, clt *client.Client) {
	fromUTC := time.Now().Add(-t.opt.UpdateInterval)
	toUTC := time.Now()

	// single page per interval (matches upstream tracker; see _original)
	rawEvents, _, err := clt.SearchEvents(ctx, fromUTC, toUTC, "", []string{"instance.join", "spiffe_svid.issue"}, t.opt.EventBatchSize, types.EventOrderDescending, "")
	if err != nil {
		log.Printf("[ERROR] Failed to fetch events: %v", err)
		return
	}

	for _, event := range rawEvents {
		data, err := json.Marshal(event)
		if err != nil {
			log.Printf("[ERROR] Failed to marshal event: %v", err)
			continue
		}

		var raw map[string]interface{}
		if err := json.Unmarshal(data, &raw); err != nil {
			log.Printf("[ERROR] Failed to unmarshal event data: %v", err)
			continue
		}

		eventType, _ := raw["event"].(string)

		// Handle instance.join events (for TPR resources)
		if eventType == "instance.join" {
			name, _ := raw["node_name"].(string)
			role, _ := raw["role"].(string)

			// Skip Proxy/Auth roles
			if role == "Proxy" || role == "Auth" {
				continue
			}

			// Ensure name and role are always present before adding and log if not
			if name == "" || role == "" {
				log.Printf("[WARNING] Skipping instance.join event: missing node_name or role")
				continue
			}

			t.addOrUpdateResource(name, role, false, "")
		}

		// Handle SPIFFE SVID issuance (for MWI tracking)
		if eventType == "spiffe_svid.issue" {
			t.resourcesMutex.Lock()
			t.mwiMetrics.SpiffeIDsIssued++
			t.resourcesMutex.Unlock()
		}
	}
}

// fetchAllResources wraps resource-specific functions to fetch all Protected Resources (TPR).
func (t *tracker) fetchAllResources(ctx context.Context, clt *client.Client) {
	t.fetchApplications(ctx, clt)
	t.fetchKubernetesClusters(ctx, clt)
	t.fetchDatabaseServers(ctx, clt)
	t.fetchWindowsDesktops(ctx, clt)
	t.fetchNodes(ctx, clt)
}

// fetchApplications fetches application servers.
// For more info: https://pkg.go.dev/github.com/gravitational/teleport/api/client#Client.GetApplicationServers
func (t *tracker) fetchApplications(ctx context.Context, clt *client.Client) {
	apps, err := clt.GetApplicationServers(ctx, "default")
	if err != nil {
		log.Printf("[ERROR] Failed to fetch applications: %v", err)
		return
	}
	for _, app := range apps {
		t.addOrUpdateResource(app.GetName(), "App", app.Expiry().IsZero(), "")
	}
}

// fetchKubernetesClusters fetches Kubernetes servers.
// For more info: https://pkg.go.dev/github.com/gravitational/teleport/api/client#Client.GetKubernetesServers
func (t *tracker) fetchKubernetesClusters(ctx context.Context, clt *client.Client) {
	servers, err := clt.GetKubernetesServers(ctx)
	if err != nil {
		log.Printf("[ERROR] Failed to fetch Kubernetes servers: %v", err)
		return
	}

	for _, server := range servers {
		t.addOrUpdateResource(server.GetName(), "Kube", server.Expiry().IsZero(), "")
	}
}

// fetchDatabaseServers fetches database servers.
// For more info: https://pkg.go.dev/github.com/gravitational/teleport/api/client#Client.GetDatabaseServers
func (t *tracker) fetchDatabaseServers(ctx context.Context, clt *client.Client) {
	databases, err := clt.GetDatabaseServers(ctx, "default")
	if err != nil {
		log.Printf("[ERROR] Failed to fetch databases: %v", err)
		return
	}
	for _, db := range databases {
		t.addOrUpdateResource(db.GetName(), "Db", db.Expiry().IsZero(), "")
	}
}

// fetchWindowsDesktops fetches Windows desktops.
// For more info: https://pkg.go.dev/github.com/gravitational/teleport/api/client#Client.GetWindowsDesktops
func (t *tracker) fetchWindowsDesktops(ctx context.Context, clt *client.Client) {
	desktops, err := clt.GetWindowsDesktops(ctx, types.WindowsDesktopFilter{})
	if err != nil {
		log.Printf("[ERROR] Failed to fetch Windows desktops: %v", err)
		return
	}
	for _, desktop := range desktops {
		t.addOrUpdateResource(desktop.GetName(), "WindowsDesktop", desktop.Expiry().IsZero(), "")
	}
}

// fetchNodes fetches SSH nodes.
// For more info: https://pkg.go.dev/github.com/gravitational/teleport/api/client#Client.GetNodes
func (t *tracker) fetchNodes(ctx context.Context, clt *client.Client) {
	nodes, err := clt.GetNodes(ctx, "default")
	if err != nil {
		log.Printf("[ERROR] Failed to fetch nodes: %v", err)
		return
	}
	for _, node := range nodes {
		t.addOrUpdateResource(node.GetHostname(), "Node", node.Expiry().IsZero(), "")
	}
}

// addOrUpdateResource adds or updates a TPR resource in memory.
func (t *tracker) addOrUpdateResource(name, kind string, static bool, instanceID string) {
	t.resourcesMutex.Lock()
	defer t.resourcesMutex.Unlock()

	t.resources[name] = Resource{
		Name:       name,
		Kind:       kind,
		Static:     static,
		LastSeen:   time.Now(),
		InstanceID: instanceID,
	}
}

// fetchMWI counts Machine & Workload Identity resources from current cluster
// state: configured Machine ID bots (ListBots) and active bot instances
// (ListBotInstances). This is more accurate than the previous approach of
// counting bot.join audit events, which only saw bots that (re)joined within
// the lookback window and collapsed every bot to a single instance.
func (t *tracker) fetchMWI(ctx context.Context, clt *client.Client) {
	bots := 0
	botSvc := clt.BotServiceClient()
	for pageToken := ""; ; {
		resp, err := botSvc.ListBots(ctx, &machineidv1pb.ListBotsRequest{PageToken: pageToken})
		if err != nil {
			log.Printf("[ERROR] Failed to list bots: %v", err)
			return
		}
		bots += len(resp.GetBots())
		if resp.GetNextPageToken() == "" {
			break
		}
		pageToken = resp.GetNextPageToken()
	}

	instances := 0
	biSvc := clt.BotInstanceServiceClient()
	for pageToken := ""; ; {
		resp, err := biSvc.ListBotInstancesV2(ctx, &machineidv1pb.ListBotInstancesV2Request{PageToken: pageToken})
		if err != nil {
			log.Printf("[ERROR] Failed to list bot instances: %v", err)
			return
		}
		instances += len(resp.GetBotInstances())
		if resp.GetNextPageToken() == "" {
			break
		}
		pageToken = resp.GetNextPageToken()
	}

	t.resourcesMutex.Lock()
	t.mwiMetrics.Bots = bots
	t.mwiMetrics.BotInstances = instances
	t.resourcesMutex.Unlock()
}

// updateMetrics updates TPR and MWI metrics and stores them in the local SQLite db.
func (t *tracker) updateMetrics() {
	t.resourcesMutex.Lock()
	defer t.resourcesMutex.Unlock()

	// Count TPR resource types
	tprCounts := map[string]int{
		"App":            0,
		"Kube":           0,
		"Db":             0,
		"WindowsDesktop": 0,
		"Node":           0,
	}

	for _, resource := range t.resources {
		tprCounts[resource.Kind]++
	}

	// MWI Bots/BotInstances are populated from current cluster state by
	// fetchMWI; SpiffeIDsIssued is accumulated from events by monitorEvents.

	timestamp := time.Now().Format("2006-01-02 15:04:05")

	// Insert TPR data
	_, err := t.db.Exec(`
	INSERT INTO tpr_data (timestamp, total_tpr, app_tpr, kube_tpr, db_tpr, windows_tpr, node_tpr)
	VALUES (?, ?, ?, ?, ?, ?, ?)`,
		timestamp, len(t.resources), tprCounts["App"], tprCounts["Kube"], tprCounts["Db"], tprCounts["WindowsDesktop"], tprCounts["Node"])
	if err != nil {
		log.Printf("[ERROR] Failed to insert TPR data: %v", err)
	}

	// Mirror the TPR snapshot to Postgres when the sink is configured (no-op otherwise).
	if err := t.pg.writeTPR(len(t.resources), tprCounts["App"], tprCounts["Kube"], tprCounts["Db"], tprCounts["WindowsDesktop"], tprCounts["Node"]); err != nil {
		log.Printf("[ERROR] Failed to insert TPR data into Postgres: %v", err)
	}

	// Insert MWI data
	_, err = t.db.Exec(`
	INSERT INTO mwi_data (timestamp, bots, bot_instances, spiffe_ids_issued)
	VALUES (?, ?, ?, ?)`,
		timestamp, t.mwiMetrics.Bots, t.mwiMetrics.BotInstances, t.mwiMetrics.SpiffeIDsIssued)
	if err != nil {
		log.Printf("[ERROR] Failed to insert MWI data: %v", err)
	}

	// Mirror the MWI snapshot to Postgres when the sink is configured (no-op otherwise).
	if err := t.pg.writeMWI(t.mwiMetrics.Bots, t.mwiMetrics.BotInstances, t.mwiMetrics.SpiffeIDsIssued); err != nil {
		log.Printf("[ERROR] Failed to insert MWI data into Postgres: %v", err)
	}

	// Reset SPIFFE counter for next interval
	t.mwiMetrics.SpiffeIDsIssued = 0
}

// writeReportsToFile writes both TPR and MWI reports to files.
func (t *tracker) writeReportsToFile() {
	t.resourcesMutex.Lock()
	defer t.resourcesMutex.Unlock()

	// Get latest TPR counts from database
	var timestamp string
	var totalTPR, appTPR, kubeTPR, dbTPR, windowsTPR, nodeTPR int

	err := t.db.QueryRow(`
	SELECT timestamp, total_tpr, app_tpr, kube_tpr, db_tpr, windows_tpr, node_tpr
	FROM tpr_data ORDER BY id DESC LIMIT 1
`).Scan(&timestamp, &totalTPR, &appTPR, &kubeTPR, &dbTPR, &windowsTPR, &nodeTPR)

	if err != nil {
		log.Printf("[ERROR] Failed to fetch latest TPR data: %v", err)
		return
	}

	// Get latest MWI counts from database
	var bots, botInstances, spiffeIDs int
	err = t.db.QueryRow(`
	SELECT bots, bot_instances, spiffe_ids_issued
	FROM mwi_data ORDER BY id DESC LIMIT 1
`).Scan(&bots, &botInstances, &spiffeIDs)

	if err != nil {
		log.Printf("[ERROR] Failed to fetch latest MWI data: %v", err)
		// Continue even if MWI data is missing
		bots, botInstances, spiffeIDs = 0, 0, 0
	}

	// Per-cycle history (only populated when -billing-day is set).
	var cycleHistory []map[string]interface{}
	if t.opt.BillingDay > 0 {
		cycleList := cycles.LastN(time.Now().UTC(), t.opt.BillingDay, t.opt.Cycles)
		cycleHistory = make([]map[string]interface{}, len(cycleList))
		for i, c := range cycleList {
			cycleHistory[i] = t.aggregateCycle(c)
		}
	}

	if t.opt.Format == "json" {
		// JSON output format
		reportData := map[string]interface{}{
			"timestamp":          timestamp,
			"teleport_proxy_url": t.opt.ProxyAddr,
			"tpr": map[string]interface{}{
				"total":            totalTPR,
				"applications":     appTPR,
				"kubernetes":       kubeTPR,
				"databases":        dbTPR,
				"windows_desktops": windowsTPR,
				"nodes":            nodeTPR,
			},
			"mwi": map[string]interface{}{
				"bots":              bots,
				"bot_instances":     botInstances,
				"spiffe_ids_issued": spiffeIDs,
			},
		}
		if cycleHistory != nil {
			reportData["billing_anchor_day"] = t.opt.BillingDay
			reportData["cycle_history"] = cycleHistory
		}

		jsonData, err := json.MarshalIndent(reportData, "", "  ")
		if err != nil {
			log.Printf("[ERROR] Failed to generate JSON report: %v", err)
			return
		}

		// Write to JSON file
		jsonFile, err := os.OpenFile("Teleport_Usage_Report.json", os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
		if err != nil {
			log.Printf("[ERROR] Could not open JSON report file: %v", err)
			return
		}
		defer jsonFile.Close()

		_, err = jsonFile.Write(jsonData)
		if err != nil {
			log.Printf("[ERROR] Failed to write JSON report: %v", err)
		}

		log.Printf("[INFO] JSON usage report updated successfully at %s", timestamp)

	} else {
		// Default text output format
		file, err := os.OpenFile("Teleport_Usage_Report.txt", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
		if err != nil {
			log.Printf("[ERROR] Could not open report file: %v", err)
			return
		}
		defer file.Close()

		// Generate report output
		output := fmt.Sprintf("\n[%s] Teleport Usage Report\n", timestamp)
		output += fmt.Sprintf("Teleport Proxy URL: %s\n", t.opt.ProxyAddr)
		output += "=================================================\n"
		output += "TELEPORT PROTECTED RESOURCES (TPR)\n"
		output += "-------------------------------------------------\n"
		output += fmt.Sprintf("Total TPR: %d\n", totalTPR)
		output += fmt.Sprintf("  - Applications: %d\n", appTPR)
		output += fmt.Sprintf("  - Kubernetes Clusters: %d\n", kubeTPR)
		output += fmt.Sprintf("  - Databases: %d\n", dbTPR)
		output += fmt.Sprintf("  - Windows Desktops: %d\n", windowsTPR)
		output += fmt.Sprintf("  - Nodes: %d\n", nodeTPR)
		output += "\n"
		output += "MACHINE & WORKLOAD IDENTITY (MWI)\n"
		output += "-------------------------------------------------\n"
		output += fmt.Sprintf("Bots: %d\n", bots)
		output += fmt.Sprintf("Bot Instances: %d\n", botInstances)
		output += fmt.Sprintf("SPIFFE IDs Issued (this period): %d\n", spiffeIDs)
		output += "=================================================\n"

		if cycleHistory != nil {
			output += "\nBILLING CYCLE HISTORY (peak within cycle for TPR/MWI, sum for SPIFFE)\n"
			output += fmt.Sprintf("Anchor day: %d\n", t.opt.BillingDay)
			output += "-------------------------------------------------\n"

			labelWidth := len("Cycle")
			for _, row := range cycleHistory {
				if l := len(row["label_display"].(string)); l > labelWidth {
					labelWidth = l
				}
			}
			labelWidth += 2

			output += fmt.Sprintf("%-*s  %-8s  %-8s  %-8s  %-8s  %-8s  %-8s  %-6s  %-8s\n",
				labelWidth, "Cycle", "Total", "Apps", "Kube", "DBs", "WinDesk", "Nodes", "Bots", "SPIFFE")
			output += strings.Repeat("-", labelWidth+2+8*8+2*7+6) + "\n"

			cell := func(width int, v interface{}) string {
				if v == nil {
					return fmt.Sprintf("%-*s", width, "n/a")
				}
				return fmt.Sprintf("%-*d", width, v.(int))
			}

			anyMissing := false
			for _, row := range cycleHistory {
				if !row["tpr_available"].(bool) || !row["mwi_available"].(bool) {
					anyMissing = true
				}
				output += fmt.Sprintf("%-*s  %s  %s  %s  %s  %s  %s  %s  %s\n",
					labelWidth, row["label_display"].(string),
					cell(8, row["total_tpr"]),
					cell(8, row["applications"]),
					cell(8, row["kubernetes"]),
					cell(8, row["databases"]),
					cell(8, row["windows_desktops"]),
					cell(8, row["nodes"]),
					cell(6, row["bots"]),
					cell(8, row["spiffe_ids_issued"]))
			}
			if anyMissing {
				output += "(n/a = no snapshot recorded in this cycle; the tracker must be running to collect data)\n"
			}
			output += "=================================================\n"
		}

		_, err = file.WriteString(output)
		if err != nil {
			log.Printf("[ERROR] Failed to write to report file: %v", err)
		}

		log.Printf("[INFO] Usage report updated successfully at %s", timestamp)
	}
}

// aggregateCycle queries SQLite for TPR/MWI activity within one billing cycle.
// Resource counts use the peak (MAX) within the window — each row is a snapshot,
// so the peak is the most defensible single number to compare against the
// portal's per-cycle figure. SPIFFE issuance uses SUM because each row records
// the count for that interval (the in-memory counter resets after each insert,
// see updateMetrics).
func (t *tracker) aggregateCycle(c cycles.Bounds) map[string]interface{} {
	startStr := c.Start.Format("2006-01-02 15:04:05")
	endStr := c.End.Format("2006-01-02 15:04:05")

	var totalTPR, appTPR, kubeTPR, dbTPR, windowsTPR, nodeTPR sql.NullInt64
	err := t.db.QueryRow(`
		SELECT MAX(total_tpr), MAX(app_tpr), MAX(kube_tpr), MAX(db_tpr),
		       MAX(windows_tpr), MAX(node_tpr)
		  FROM tpr_data
		 WHERE timestamp >= ? AND timestamp < ?`,
		startStr, endStr,
	).Scan(&totalTPR, &appTPR, &kubeTPR, &dbTPR, &windowsTPR, &nodeTPR)
	if err != nil {
		log.Printf("[ERROR] aggregateCycle TPR query failed for %s: %v", c.Label, err)
	}

	var botsMax, instMax, spiffeSum sql.NullInt64
	err = t.db.QueryRow(`
		SELECT MAX(bots), MAX(bot_instances), COALESCE(SUM(spiffe_ids_issued), 0)
		  FROM mwi_data
		 WHERE timestamp >= ? AND timestamp < ?`,
		startStr, endStr,
	).Scan(&botsMax, &instMax, &spiffeSum)
	if err != nil {
		log.Printf("[ERROR] aggregateCycle MWI query failed for %s: %v", c.Label, err)
	}

	display := c.Label
	if c.InProgress {
		display += " (in progress)"
	}

	// MAX(...) returns NULL when no rows match — that's our signal for "no data
	// recorded for this cycle" (e.g. tracker wasn't running yet). Preserve the
	// distinction between "no data" and "real zero" by returning nil in that
	// case; the text formatter renders it as n/a and JSON serialises it as null.
	tprAvailable := totalTPR.Valid
	mwiAvailable := botsMax.Valid

	asValue := func(v sql.NullInt64, available bool) interface{} {
		if !available || !v.Valid {
			return nil
		}
		return int(v.Int64)
	}

	return map[string]interface{}{
		"label":             c.Label,
		"label_display":     display,
		"start":             c.Start.Format(time.RFC3339),
		"end":               c.End.Format(time.RFC3339),
		"in_progress":       c.InProgress,
		"tpr_available":     tprAvailable,
		"mwi_available":     mwiAvailable,
		"total_tpr":         asValue(totalTPR, tprAvailable),
		"applications":      asValue(appTPR, tprAvailable),
		"kubernetes":        asValue(kubeTPR, tprAvailable),
		"databases":         asValue(dbTPR, tprAvailable),
		"windows_desktops":  asValue(windowsTPR, tprAvailable),
		"nodes":             asValue(nodeTPR, tprAvailable),
		"bots":              asValue(botsMax, mwiAvailable),
		"bot_instances":     asValue(instMax, mwiAvailable),
		"spiffe_ids_issued": asValue(spiffeSum, mwiAvailable),
	}
}

// cleanupStaleResources removes stale resources (older than configured update interval) from memory.
func (t *tracker) cleanupStaleResources() {
	t.resourcesMutex.Lock()
	defer t.resourcesMutex.Unlock()

	now := time.Now()
	for name, resource := range t.resources {
		if now.Sub(resource.LastSeen) > t.opt.UpdateInterval {
			delete(t.resources, name)
		}
	}
}
