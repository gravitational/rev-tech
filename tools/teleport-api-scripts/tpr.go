package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/gravitational/teleport/api/client"
	"github.com/gravitational/teleport/api/types"
	_ "github.com/mattn/go-sqlite3"
)

// Configuration Variables - Modify these to customize the script behavior
var (
	// Teleport cluster configuration
	teleportProxyURL = "proxy.example.com:443" // Change to your Teleport proxy URL
	useIdentityFile  = false                   // Set to true to use identity file authentication
	identityFilePath = "/path/to/identity"     // Path to identity file (only used if useIdentityFile = true)

	// Monitoring configuration
	updateInterval = 1 * time.Hour // How often to refresh TPR data (default: 1 hour)

	// Report configuration
	reportFormat = "text" // Options: "json" or "text" (default: text)

	// Data retention configuration
	dataRetentionDays = 30 // Number of days to keep historical data (default: 30 days)

	// Performance configuration
	eventBatchSize = 5000 // Number of events to fetch per batch for instance.join monitoring (default: 5000)
)

// Represents a tracked Teleport Protected Resource (TPR).
// More info: https://goteleport.com/docs/usage-billing/#teleport-protected-resources
type Resource struct {
	Name       string
	Kind       string
	Static     bool
	LastSeen   time.Time
	InstanceID string
}

// Represents Machine & Workload Identity (MWI) usage tracking
type MWIUsage struct {
	Bots            int // Unique bot names
	BotInstances    int // Individual bot instances
	SpiffeIDsIssued int // SPIFFE IDs issued in the period
}

var (
	resources      = make(map[string]Resource) // In-memory map to track active resources (TPR)
	botInstances   = make(map[string]string)   // Track bot instances: bot_name -> instance_id
	mwiMetrics     MWIUsage                    // MWI usage metrics
	resourcesMutex sync.Mutex                  // Mutex to ensure safe concurrent access
	logFile        *os.File                    // File handle for logging & report outputs
	db             *sql.DB                     // SQLite database connection

	billingDayAnchor int // -billing-day value (0 = disabled)
	cyclesCount      int // -cycles value
)

// cycleBounds is a half-open billing-cycle window [Start, End).
type cycleBounds struct {
	Start      time.Time
	End        time.Time
	Label      string
	InProgress bool
}

func daysIn(year int, month time.Month) int {
	return time.Date(year, month+1, 0, 0, 0, 0, 0, time.UTC).Day()
}

func cycleStart(year int, month time.Month, anchor int) time.Time {
	d := anchor
	if last := daysIn(year, month); d > last {
		d = last
	}
	return time.Date(year, month, d, 0, 0, 0, 0, time.UTC)
}

func cycleContaining(t time.Time, anchor int) cycleBounds {
	t = t.UTC()
	start := cycleStart(t.Year(), t.Month(), anchor)
	if t.Before(start) {
		prevYear, prevMonth := t.Year(), t.Month()-1
		if prevMonth < 1 {
			prevYear--
			prevMonth = 12
		}
		start = cycleStart(prevYear, prevMonth, anchor)
	}
	nextYear, nextMonth := start.Year(), start.Month()+1
	if nextMonth > 12 {
		nextYear++
		nextMonth = 1
	}
	end := cycleStart(nextYear, nextMonth, anchor)
	return cycleBounds{
		Start: start,
		End:   end,
		Label: fmt.Sprintf("%s - %s",
			start.Format("2 Jan 2006"),
			end.Add(-24*time.Hour).Format("2 Jan 2006")),
	}
}

func lastNCycles(now time.Time, anchor, n int) []cycleBounds {
	current := cycleContaining(now, anchor)
	current.InProgress = true
	out := []cycleBounds{current}
	for i := 0; i < n; i++ {
		prev := out[len(out)-1].Start.Add(-24 * time.Hour)
		out = append(out, cycleContaining(prev, anchor))
	}
	for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
		out[i], out[j] = out[j], out[i]
	}
	return out
}

// Initializes logging, connects to a Teleport cluster, and continuously tracks protected resources (TPRs) and MWI.
// 1. Initializes Logging & Database: Sets up structured logging and a SQLite database for TPR/MWI storage.
// 2. Connects to Teleport API: Establishes a client session and retrieves active resources.
// 3. Monitors & Updates: Fetches resource data, tracks instance/bot join events, and updates counts in SQLite.
// 4. Writes Reports: Aggregates resource and MWI metrics and writes reports to files.
// 5. Runs Periodic Updates: Refreshes data, logs changes, and cleans up stale records based on configured interval.
func main() {
	// Command-line flags
	proxyFlag := flag.String(
		"proxy",
		teleportProxyURL,
		"Teleport proxy address (e.g. teleport.example.com:443)",
	)

	formatFlag := flag.String(
		"format",
		"text",
		"Output file type - text or json",
	)

	identityFileFlag := flag.String(
		"identity_file",
		"",
		"Path to Teleport identity file (optional - enables use of an identity file instead of ambient tsh credentials)",
	)

	billingDayFlag := flag.Int(
		"billing-day",
		0,
		"Billing cycle anchor day (1-31). When set, an additional per-cycle history section is included in each report.",
	)

	cyclesFlag := flag.Int(
		"cycles",
		3,
		"Number of completed cycles to include alongside the in-progress cycle (only used with -billing-day).",
	)

	flag.Parse()

	teleportProxyURL = *proxyFlag
	if !strings.Contains(teleportProxyURL, ":") {
		log.Fatalf("invalid proxy address %q (expected hostname:port)", teleportProxyURL)
	}

	// Output format handling
	reportFormat = strings.ToLower(strings.TrimSpace(*formatFlag))
	if reportFormat != "text" && reportFormat != "json" {
		log.Fatalf("invalid -format %q (expected text or json)", reportFormat)
	}

	if *identityFileFlag != "" {
		useIdentityFile = true
		identityFilePath = *identityFileFlag
		// Validation
		if _, err := os.Stat(identityFilePath); err != nil {
			log.Fatalf("identity file not accessible: %v", err)
		}
	}

	billingDayAnchor = *billingDayFlag
	if billingDayAnchor < 0 || billingDayAnchor > 31 {
		log.Fatalf("invalid -billing-day %d (expected 1-31, or 0 to disable)", billingDayAnchor)
	}
	cyclesCount = *cyclesFlag
	if cyclesCount < 0 {
		log.Fatalf("invalid -cycles %d (must be >= 0)", cyclesCount)
	}
	if billingDayAnchor > 0 {
		oldest := lastNCycles(time.Now().UTC(), billingDayAnchor, cyclesCount)[0].Start
		spanDays := int(time.Since(oldest).Hours() / 24)
		if spanDays > dataRetentionDays {
			log.Printf("[WARN] Requested -cycles=%d spans ~%d days but dataRetentionDays=%d; older cycles will be empty until SQLite history catches up.",
				cyclesCount, spanDays, dataRetentionDays)
		}
	}

	initDatabase()
	defer db.Close()

	ctx := context.Background()

	// Build credentials based on configuration
	var credentials []client.Credentials
	if useIdentityFile {
		credentials = []client.Credentials{
			client.LoadIdentityFile(identityFilePath),
		}
	} else {
		credentials = []client.Credentials{
			client.LoadProfile("", ""),
		}
	}

	clt, err := client.New(ctx, client.Config{
		Addrs:       []string{teleportProxyURL},
		Credentials: credentials,
	})
	if err != nil {
		log.Fatalf("Failed to create client: %v", err)
	}
	defer clt.Close()

	log.Println("[INFO] Teleport Resource Tracker is running...")

	// Initial data collection & report generation
	fetchAllResources(ctx, clt)
	monitorEvents(ctx, clt)
	updateMetrics()
	writeReportsToFile()

	// Start periodic updates based on configured interval
	go func() {
		time.Sleep(updateInterval)

		for {
			fetchAllResources(ctx, clt)
			monitorEvents(ctx, clt)
			updateMetrics()
			writeReportsToFile()
			cleanupStaleResources()
			time.Sleep(updateInterval)
		}
	}()

	select {} // Keeps the program running indefinitely until process is killed
}

// Creates an SQLite database file for storing TPR and MWI data.
// Also removes old data based on configured retention period to protect against storage bloat.
func initDatabase() {
	var err error
	db, err = sql.Open("sqlite3", "teleport_usage_data.db")
	if err != nil {
		log.Fatalf("Failed to open database: %v", err)
	}

	// Create TPR table
	_, err = db.Exec(`
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
		log.Fatalf("Failed to create TPR table: %v", err)
	}

	// Create MWI table
	_, err = db.Exec(`
	CREATE TABLE IF NOT EXISTS mwi_data (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		timestamp TEXT,
		bots INTEGER,
		bot_instances INTEGER,
		spiffe_ids_issued INTEGER
		)
	`)
	if err != nil {
		log.Fatalf("Failed to create MWI table: %v", err)
	}

	// Cleanup old records based on configured retention period
	_, err = db.Exec(fmt.Sprintf(`DELETE FROM tpr_data WHERE timestamp < datetime('now', '-%d days')`, dataRetentionDays))
	if err != nil {
		log.Printf("[ERROR] Failed to clean up old TPR records: %v", err)
	}

	_, err = db.Exec(fmt.Sprintf(`DELETE FROM mwi_data WHERE timestamp < datetime('now', '-%d days')`, dataRetentionDays))
	if err != nil {
		log.Printf("[ERROR] Failed to clean up old MWI records: %v", err)
	}
}

// Watches for instance.join, bot.join, and spiffe_svid events to detect new resources and MWI activity.
func monitorEvents(ctx context.Context, clt *client.Client) {
	fromUTC := time.Now().Add(-updateInterval)
	toUTC := time.Now()
	var nextKey string

	rawEvents, newNextKey, err := clt.SearchEvents(ctx, fromUTC, toUTC, "", []string{"instance.join", "bot.join", "spiffe_svid.issue"}, eventBatchSize, types.EventOrderDescending, nextKey)
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

			addOrUpdateResource(name, role, false, "")
		}

		// Handle bot.join events (for MWI tracking)
		if eventType == "bot.join" {
			name, _ := raw["bot_name"].(string)
			instanceID, _ := raw["bot_instance_id"].(string)

			if name == "" {
				log.Printf("[WARNING] Skipping bot.join event: missing bot_name")
				continue
			}

			trackBotInstance(name, instanceID)
		}

		// Handle SPIFFE SVID issuance (for MWI tracking)
		if eventType == "spiffe_svid.issue" {
			resourcesMutex.Lock()
			mwiMetrics.SpiffeIDsIssued++
			resourcesMutex.Unlock()
		}
	}

	// Preserve pagination state as needed
	if newNextKey != "" {
		nextKey = newNextKey
	}
}

// Wraps Resource-Specific Functions to Fetch All Protected Resources (TPR)
func fetchAllResources(ctx context.Context, clt *client.Client) {
	fetchApplications(ctx, clt)
	fetchKubernetesClusters(ctx, clt)
	fetchDatabaseServers(ctx, clt)
	fetchWindowsDesktops(ctx, clt)
	fetchNodes(ctx, clt)
}

// Fetch Applications
// For more info: https://pkg.go.dev/github.com/gravitational/teleport/api/client#Client.GetApplicationServers
func fetchApplications(ctx context.Context, clt *client.Client) {
	apps, err := clt.GetApplicationServers(ctx, "default")
	if err != nil {
		log.Printf("[ERROR] Failed to fetch applications: %v", err)
		return
	}
	for _, app := range apps {
		addOrUpdateResource(app.GetName(), "App", app.Expiry().IsZero(), "")
	}
}

// Fetch Kubernetes Clusters
// For more info: https://pkg.go.dev/github.com/gravitational/teleport/api/client#Client.GetKubernetesServers
func fetchKubernetesClusters(ctx context.Context, clt *client.Client) {
	servers, err := clt.GetKubernetesServers(ctx)
	if err != nil {
		log.Printf("[ERROR] Failed to fetch Kubernetes servers: %v", err)
		return
	}

	for _, server := range servers {
		addOrUpdateResource(server.GetName(), "Kube", server.Expiry().IsZero(), "")
	}
}

// Fetch Database Servers
// For more info: https://pkg.go.dev/github.com/gravitational/teleport/api/client#Client.GetDatabaseServers
func fetchDatabaseServers(ctx context.Context, clt *client.Client) {
	databases, err := clt.GetDatabaseServers(ctx, "default")
	if err != nil {
		log.Printf("[ERROR] Failed to fetch databases: %v", err)
		return
	}
	for _, db := range databases {
		addOrUpdateResource(db.GetName(), "Db", db.Expiry().IsZero(), "")
	}
}

// Fetch Windows Desktops
// For more info: https://pkg.go.dev/github.com/gravitational/teleport/api/client#Client.GetWindowsDesktops
func fetchWindowsDesktops(ctx context.Context, clt *client.Client) {
	desktops, err := clt.GetWindowsDesktops(ctx, types.WindowsDesktopFilter{})
	if err != nil {
		log.Printf("[ERROR] Failed to fetch Windows desktops: %v", err)
		return
	}
	for _, desktop := range desktops {
		addOrUpdateResource(desktop.GetName(), "WindowsDesktop", desktop.Expiry().IsZero(), "")
	}
}

// Fetch SSH Nodes
// For more info: https://pkg.go.dev/github.com/gravitational/teleport/api/client#Client.GetNodes
func fetchNodes(ctx context.Context, clt *client.Client) {
	nodes, err := clt.GetNodes(ctx, "default")
	if err != nil {
		log.Printf("[ERROR] Failed to fetch nodes: %v", err)
		return
	}
	for _, node := range nodes {
		addOrUpdateResource(node.GetHostname(), "Node", node.Expiry().IsZero(), "")
	}
}

// Add or update a TPR resource in memory
func addOrUpdateResource(name, kind string, static bool, instanceID string) {
	resourcesMutex.Lock()
	defer resourcesMutex.Unlock()

	resources[name] = Resource{
		Name:       name,
		Kind:       kind,
		Static:     static,
		LastSeen:   time.Now(),
		InstanceID: instanceID,
	}
}

// Track bot instances for MWI metrics
func trackBotInstance(botName, instanceID string) {
	resourcesMutex.Lock()
	defer resourcesMutex.Unlock()

	// Check if this is a new bot or a new instance
	if existingInstanceID, exists := botInstances[botName]; exists {
		if existingInstanceID != instanceID {
			log.Printf("[INFO] New bot instance detected for %s (old: %s, new: %s)", botName, existingInstanceID, instanceID)
		}
	}

	botInstances[botName] = instanceID
}

// Update TPR and MWI metrics and store in local SQLite db
func updateMetrics() {
	resourcesMutex.Lock()
	defer resourcesMutex.Unlock()

	// Count TPR resource types
	tprCounts := map[string]int{
		"App":            0,
		"Kube":           0,
		"Db":             0,
		"WindowsDesktop": 0,
		"Node":           0,
	}

	for _, resource := range resources {
		tprCounts[resource.Kind]++
	}

	// Calculate MWI metrics
	mwiMetrics.Bots = len(botInstances)
	mwiMetrics.BotInstances = len(botInstances) // In this implementation, we track one instance per bot

	timestamp := time.Now().Format("2006-01-02 15:04:05")

	// Insert TPR data
	_, err := db.Exec(`
	INSERT INTO tpr_data (timestamp, total_tpr, app_tpr, kube_tpr, db_tpr, windows_tpr, node_tpr)
	VALUES (?, ?, ?, ?, ?, ?, ?)`,
		timestamp, len(resources), tprCounts["App"], tprCounts["Kube"], tprCounts["Db"], tprCounts["WindowsDesktop"], tprCounts["Node"])
	if err != nil {
		log.Printf("[ERROR] Failed to insert TPR data: %v", err)
	}

	// Insert MWI data
	_, err = db.Exec(`
	INSERT INTO mwi_data (timestamp, bots, bot_instances, spiffe_ids_issued)
	VALUES (?, ?, ?, ?)`,
		timestamp, mwiMetrics.Bots, mwiMetrics.BotInstances, mwiMetrics.SpiffeIDsIssued)
	if err != nil {
		log.Printf("[ERROR] Failed to insert MWI data: %v", err)
	}

	// Reset SPIFFE counter for next interval
	mwiMetrics.SpiffeIDsIssued = 0
}

// Write both TPR and MWI reports to files
func writeReportsToFile() {
	resourcesMutex.Lock()
	defer resourcesMutex.Unlock()

	// Get latest TPR counts from database
	var timestamp string
	var totalTPR, appTPR, kubeTPR, dbTPR, windowsTPR, nodeTPR int

	err := db.QueryRow(`
	SELECT timestamp, total_tpr, app_tpr, kube_tpr, db_tpr, windows_tpr, node_tpr
	FROM tpr_data ORDER BY id DESC LIMIT 1
`).Scan(&timestamp, &totalTPR, &appTPR, &kubeTPR, &dbTPR, &windowsTPR, &nodeTPR)

	if err != nil {
		log.Printf("[ERROR] Failed to fetch latest TPR data: %v", err)
		return
	}

	// Get latest MWI counts from database
	var bots, botInstances, spiffeIDs int
	err = db.QueryRow(`
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
	if billingDayAnchor > 0 {
		cycles := lastNCycles(time.Now().UTC(), billingDayAnchor, cyclesCount)
		cycleHistory = make([]map[string]interface{}, len(cycles))
		for i, c := range cycles {
			cycleHistory[i] = aggregateCycle(c)
		}
	}

	if reportFormat == "json" {
		// JSON output format
		reportData := map[string]interface{}{
			"timestamp":          timestamp,
			"teleport_proxy_url": teleportProxyURL,
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
			reportData["billing_anchor_day"] = billingDayAnchor
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
		output += fmt.Sprintf("Teleport Proxy URL: %s\n", teleportProxyURL)
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
			output += fmt.Sprintf("Anchor day: %d\n", billingDayAnchor)
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
func aggregateCycle(c cycleBounds) map[string]interface{} {
	startStr := c.Start.Format("2006-01-02 15:04:05")
	endStr := c.End.Format("2006-01-02 15:04:05")

	var totalTPR, appTPR, kubeTPR, dbTPR, windowsTPR, nodeTPR sql.NullInt64
	err := db.QueryRow(`
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
	err = db.QueryRow(`
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

// Cleanup stale resources (older than configured update interval) from memory
func cleanupStaleResources() {
	resourcesMutex.Lock()
	defer resourcesMutex.Unlock()

	now := time.Now()
	for name, resource := range resources {
		if now.Sub(resource.LastSeen) > updateInterval {
			delete(resources, name)
		}
	}
}
