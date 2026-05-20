package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/gravitational/teleport/api/client"
	"github.com/gravitational/teleport/api/defaults"
	"github.com/gravitational/teleport/api/types"
)

// Configuration Variables - Modify these to customize the script behavior
var (
	// Teleport cluster configuration
	teleportProxyURL = "proxy.example.com:443" // Default proxy URL
	useIdentityFile  = false                   // Set to true to use identity file authentication
	identityFilePath = "/path/to/identity"     // Path to identity file (only used if useIdentityFile = true)

	// Time range configuration
	daysBack = 30 // Number of days back to analyze (default: 30 days)

	// Report configuration
	reportFormat = "text" // Options: "json" or "text"

	// Performance configuration
	batchSize = 5000 // Number of events to fetch per batch

	// Output filenames
	outputFilenameText = "Teleport_Active_Users.txt"
	outputFilenameJson = "Teleport_Active_Users.json"
)

// UserResourceUsage tracks Zero Trust Access usage for each user
type UserResourceUsage struct {
	LoginCount  int `json:"login_count"`
	SSH         int `json:"ssh"`
	Kubernetes  int `json:"kubernetes"`
	Database    int `json:"database"`
	Application int `json:"application"`
	Desktop     int `json:"desktop"`
}

// UserIGUsage tracks Identity Governance usage for each user
type UserIGUsage struct {
	AccessRequestsCreated  int `json:"access_requests_created"`
	AccessRequestsReviewed int `json:"access_requests_reviewed"`
	AccessListsMemberships int `json:"access_lists_memberships"`
	AccessListsReviewed    int `json:"access_lists_reviewed"`
	SAMLIDPSessions        int `json:"saml_idp_sessions"`
}

// UserKindLabel is what we print in the table.
type UserKindLabel string

const (
	UserKindHuman UserKindLabel = "Human"
	UserKindBot   UserKindLabel = "Bot"
)

// classifyUserKind tries to determine whether an event user is human or bot.
// It defaults to Human if the field is missing/unknown.
func classifyUserKind(raw map[string]interface{}) UserKindLabel {
	v, ok := raw["user_kind"]
	if !ok || v == nil {
		return UserKindHuman
	}

	switch t := v.(type) {
	case string:
		s := strings.ToLower(t)
		// common possibilities: "bot", "human", "USER_KIND_BOT", "USER_KIND_HUMAN", etc.
		if strings.Contains(s, "bot") {
			return UserKindBot
		}
		if strings.Contains(s, "human") {
			return UserKindHuman
		}
		return UserKindHuman
	case float64:
		// If user_kind is an enum encoded as a number, we can't be 100% sure here.
		// Conventionally: 0=unspecified, 1=human, 2=bot (common pattern).
		if int(t) == 2 {
			return UserKindBot
		}
		return UserKindHuman
	default:
		return UserKindHuman
	}
}

// sortedKeys returns the sorted keys of a string-keyed map.
func sortedKeys[T any](m map[string]T) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

// cycleBounds is a half-open billing-cycle window [Start, End).
type cycleBounds struct {
	Start      time.Time
	End        time.Time
	Label      string
	InProgress bool
}

// daysIn returns the number of days in the given year/month.
func daysIn(year int, month time.Month) int {
	return time.Date(year, month+1, 0, 0, 0, 0, 0, time.UTC).Day()
}

// cycleStart returns the anchor-day 00:00 UTC for year/month, clamped to the
// last day of the month when anchor exceeds that month's length.
func cycleStart(year int, month time.Month, anchor int) time.Time {
	d := anchor
	if last := daysIn(year, month); d > last {
		d = last
	}
	return time.Date(year, month, d, 0, 0, 0, 0, time.UTC)
}

// cycleContaining returns the billing cycle whose half-open window contains t.
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

// lastNCycles returns the cycle containing now plus n fully-completed preceding
// cycles, oldest-first. The cycle containing now is marked InProgress.
func lastNCycles(now time.Time, anchor, n int) []cycleBounds {
	current := cycleContaining(now, anchor)
	current.InProgress = true
	out := []cycleBounds{current}
	for i := 0; i < n; i++ {
		// Pick any instant inside the previous cycle (one day before this start).
		prev := out[len(out)-1].Start.Add(-24 * time.Hour)
		out = append(out, cycleContaining(prev, anchor))
	}
	// Reverse to oldest-first.
	for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
		out[i], out[j] = out[j], out[i]
	}
	return out
}

// cycleAccum collects per-user activity for a single billing cycle (or, when
// no -billing-day is set, the whole rolling window).
type cycleAccum struct {
	userResourceUsage map[string]*UserResourceUsage
	userIGUsage       map[string]*UserIGUsage
	userKind          map[string]UserKindLabel
	totalLogins       int
}

func newCycleAccum() *cycleAccum {
	return &cycleAccum{
		userResourceUsage: make(map[string]*UserResourceUsage),
		userIGUsage:       make(map[string]*UserIGUsage),
		userKind:          make(map[string]UserKindLabel),
	}
}

// ingest applies one decoded audit event to this accumulator.
func (a *cycleAccum) ingest(raw map[string]interface{}) {
	user, ok := raw["user"].(string)
	if !ok || user == "" {
		return
	}
	kind := classifyUserKind(raw)
	if existing, ok := a.userKind[user]; !ok {
		a.userKind[user] = kind
	} else if existing != UserKindBot && kind == UserKindBot {
		a.userKind[user] = UserKindBot
	}
	eventType, ok := raw["event"].(string)
	if !ok {
		return
	}
	switch eventType {
	case "user.login":
		if a.userResourceUsage[user] == nil {
			a.userResourceUsage[user] = &UserResourceUsage{}
		}
		if raw["success"] == true {
			a.userResourceUsage[user].LoginCount++
			a.totalLogins++
		}
	case "session.start":
		if a.userResourceUsage[user] == nil {
			a.userResourceUsage[user] = &UserResourceUsage{}
		}
		if kubeCluster, exists := raw["kubernetes_cluster"]; exists && kubeCluster != nil {
			a.userResourceUsage[user].Kubernetes++
		} else {
			a.userResourceUsage[user].SSH++
		}
	case "db.session.start":
		if a.userResourceUsage[user] == nil {
			a.userResourceUsage[user] = &UserResourceUsage{}
		}
		a.userResourceUsage[user].Database++
	case "app.session.start":
		if a.userResourceUsage[user] == nil {
			a.userResourceUsage[user] = &UserResourceUsage{}
		}
		a.userResourceUsage[user].Application++
	case "windows.desktop.session.start":
		if a.userResourceUsage[user] == nil {
			a.userResourceUsage[user] = &UserResourceUsage{}
		}
		a.userResourceUsage[user].Desktop++
	case "kube.request":
		if a.userResourceUsage[user] == nil {
			a.userResourceUsage[user] = &UserResourceUsage{}
		}
		a.userResourceUsage[user].Kubernetes++
	case "access_request.create":
		if a.userIGUsage[user] == nil {
			a.userIGUsage[user] = &UserIGUsage{}
		}
		a.userIGUsage[user].AccessRequestsCreated++
	case "access_request.review":
		if a.userIGUsage[user] == nil {
			a.userIGUsage[user] = &UserIGUsage{}
		}
		a.userIGUsage[user].AccessRequestsReviewed++
	case "access_list.member.create", "access_list.member.update":
		if a.userIGUsage[user] == nil {
			a.userIGUsage[user] = &UserIGUsage{}
		}
		a.userIGUsage[user].AccessListsMemberships++
	case "access_list.review":
		if a.userIGUsage[user] == nil {
			a.userIGUsage[user] = &UserIGUsage{}
		}
		a.userIGUsage[user].AccessListsReviewed++
	case "saml.idp.auth":
		if a.userIGUsage[user] == nil {
			a.userIGUsage[user] = &UserIGUsage{}
		}
		a.userIGUsage[user].SAMLIDPSessions++
	}
}

// cycleSummary holds the filtered + counted view of one accumulator.
type cycleSummary struct {
	ztaMAUAll     map[string]*UserResourceUsage
	igMAUAll      map[string]*UserIGUsage
	ztaHumanCount int
	igHumanCount  int
	mwiBotCount   int
}

func (a *cycleAccum) summarize() cycleSummary {
	ztaMAUAll := make(map[string]*UserResourceUsage)
	for user, usage := range a.userResourceUsage {
		if usage.SSH > 0 || usage.Kubernetes > 0 || usage.Database > 0 ||
			usage.Application > 0 || usage.Desktop > 0 {
			ztaMAUAll[user] = usage
		}
	}
	igMAUAll := make(map[string]*UserIGUsage)
	for user, usage := range a.userIGUsage {
		if usage.AccessRequestsCreated > 0 || usage.AccessRequestsReviewed > 0 ||
			usage.AccessListsMemberships > 0 || usage.AccessListsReviewed > 0 ||
			usage.SAMLIDPSessions > 0 {
			igMAUAll[user] = usage
		}
	}
	ztaHumanCount := 0
	igHumanCount := 0
	botSet := make(map[string]struct{})
	for user := range ztaMAUAll {
		if a.userKind[user] == UserKindBot {
			botSet[user] = struct{}{}
		} else {
			ztaHumanCount++
		}
	}
	for user := range igMAUAll {
		if a.userKind[user] == UserKindBot {
			botSet[user] = struct{}{}
		} else {
			igHumanCount++
		}
	}
	return cycleSummary{
		ztaMAUAll:     ztaMAUAll,
		igMAUAll:      igMAUAll,
		ztaHumanCount: ztaHumanCount,
		igHumanCount:  igHumanCount,
		mwiBotCount:   len(botSet),
	}
}

func main() {
	// Command-line flags
	proxyFlag := flag.String(
		"proxy",
		teleportProxyURL,
		"Teleport proxy address (e.g. teleport.example.com:443)",
	)

	identityFileFlag := flag.String(
		"identity_file",
		"",
		"Path to Teleport identity file (optional - enables use of an identity file instead of ambient tsh credentials)",
	)

	formatFlag := flag.String(
		"format",
		"text",
		"Output file type - text or json",
	)

	billingDayFlag := flag.Int(
		"billing-day",
		0,
		"Billing cycle anchor day (1-31). When set, the report is aligned to Teleport billing cycles instead of a rolling daysBack window.",
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

	billingDay := *billingDayFlag
	if billingDay < 0 || billingDay > 31 {
		log.Fatalf("invalid -billing-day %d (expected 1-31, or 0 to disable)", billingDay)
	}
	billingDayAnchor = billingDay
	cyclesCount := *cyclesFlag
	if cyclesCount < 0 {
		log.Fatalf("invalid -cycles %d (must be >= 0)", cyclesCount)
	}

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
		log.Fatalf("failed to create client: %v", err)
	}
	defer clt.Close()

	// Define the time range and per-cycle accumulators.
	var (
		fromUTC, toUTC time.Time
		cycles         []cycleBounds
		accums         []*cycleAccum
		single         *cycleAccum
	)
	if billingDay > 0 {
		now := time.Now().UTC()
		cycles = lastNCycles(now, billingDay, cyclesCount)
		accums = make([]*cycleAccum, len(cycles))
		for i := range accums {
			accums[i] = newCycleAccum()
		}
		fromUTC = cycles[0].Start
		toUTC = now
		log.Printf("[INFO] Billing-cycle mode: anchor=%d, %d cycle(s) from %s to %s",
			billingDay, len(cycles), fromUTC.Format("2006-01-02"), toUTC.Format("2006-01-02"))
		if now.Sub(fromUTC) > 90*24*time.Hour {
			log.Printf("[WARN] Requested window spans %.0f days; older cycles may be empty due to audit log retention.",
				now.Sub(fromUTC).Hours()/24)
		}
	} else {
		fromUTC = time.Now().AddDate(0, 0, -daysBack)
		toUTC = time.Now()
		single = newCycleAccum()
	}

	nextKey := ""

	// Event types to track for both ZTA MAU and IG MAU
	eventTypes := []string{
		// ZTA MAU events (resource access)
		"user.login",
		"session.start",
		"db.session.start",
		"app.session.start",
		"windows.desktop.session.start",
		"kube.request",
		// IG MAU events (identity governance)
		"access_request.create",
		"access_request.review",
		"access_list.member.create",
		"access_list.member.update",
		"access_list.review",
		"saml.idp.auth",
	}

	for {
		log.Println("Fetching batch of events...")
		rawEvents, newNextKey, err := clt.SearchEvents(
			ctx,
			fromUTC,
			toUTC,
			defaults.Namespace,
			eventTypes,
			batchSize,
			types.EventOrderDescending,
			nextKey,
		)
		if err != nil {
			log.Fatalf("Failed to fetch events: %v", err)
		}
		if len(rawEvents) == 0 {
			break
		}

		for _, event := range rawEvents {
			data, err := json.Marshal(event)
			if err != nil {
				log.Printf("Failed to marshal event: %v", err)
				continue
			}

			var raw map[string]interface{}
			if err := json.Unmarshal(data, &raw); err != nil {
				log.Printf("Failed to unmarshal event data: %v", err)
				continue
			}

			if billingDay > 0 {
				et := event.GetTime().UTC()
				idx := -1
				for i, c := range cycles {
					if !et.Before(c.Start) && et.Before(c.End) {
						idx = i
						break
					}
				}
				if idx < 0 {
					continue
				}
				accums[idx].ingest(raw)
			} else {
				single.ingest(raw)
			}
		}

		// If no next page, break
		if newNextKey == "" || newNextKey == nextKey {
			break
		}
		nextKey = newNextKey
	}

	if billingDay > 0 {
		summaries := make([]cycleSummary, len(cycles))
		for i, a := range accums {
			summaries[i] = a.summarize()
		}
		writePerCycleReport(cycles, accums, summaries)
	} else {
		s := single.summarize()
		writeUserReport(s.ztaMAUAll, s.igMAUAll, single.userKind, single.totalLogins, s.ztaHumanCount, s.igHumanCount, s.mwiBotCount)
	}
}

// Writes the user activity report to a file in either JSON or text format
func writeUserReport(
	ztaMAU map[string]*UserResourceUsage,
	igMAU map[string]*UserIGUsage,
	userKind map[string]UserKindLabel,
	totalLogins int,
	ztaHumanCount int,
	igHumanCount int,
	mwiBotCount int,
) {
	timestamp := time.Now().Format("2006-01-02 15:04:05")

	if reportFormat == "json" {
		// JSON Output
		reportData := map[string]interface{}{
			"teleport_proxy_url":      teleportProxyURL,
			"timestamp":               timestamp,
			"total_ztamau_users":      ztaHumanCount,
			"total_igmau_users":       igHumanCount,
			"total_mwi_bots":          mwiBotCount,
			"total_successful_logins": totalLogins,
			"user_kind":               userKind,
			"zta_resource_usage_all":  ztaMAU,
			"ig_feature_usage_all":    igMAU,
		}

		jsonData, err := json.MarshalIndent(reportData, "", "  ")
		if err != nil {
			log.Fatalf("Failed to generate JSON report: %v", err)
		}

		// Write JSON report to file
		jsonFile, err := os.OpenFile(outputFilenameJson, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
		if err != nil {
			log.Fatalf("Failed to open JSON report file: %v", err)
		}
		defer jsonFile.Close()

		_, err = jsonFile.Write(jsonData)
		if err != nil {
			log.Fatalf("Failed to write JSON report: %v", err)
		}

		log.Printf("[INFO] JSON report successfully written to %s at %s", outputFilenameJson, timestamp)

	} else {
		// Default Text Output
		file, err := os.OpenFile(outputFilenameText, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
		if err != nil {
			log.Fatalf("Failed to open report file: %v", err)
		}
		defer file.Close()

		// Generate report header
		output := fmt.Sprintf("\n[%s] Teleport Active Users Report\n", timestamp)
		output += fmt.Sprintf("Teleport Proxy URL: %s\n", teleportProxyURL)
		output += "=================================================\n"
		output += fmt.Sprintf("Total Zero Trust Access MAU (ZTA MAU): %d\n", ztaHumanCount)
		output += fmt.Sprintf("Total Identity Governance MAU (IG MAU): %d\n", igHumanCount)
		output += fmt.Sprintf("Total Machine and Workload Identity Bot users (MWI): %d\n", mwiBotCount)
		output += fmt.Sprintf("Total Successful Logins: %d\n", totalLogins)
		output += "=================================================\n\n"

		output += formatUserTables(ztaMAU, igMAU, userKind)

		_, err = file.WriteString(output)
		if err != nil {
			log.Fatalf("Failed to write to report file: %v", err)
		}

		log.Printf("[INFO] Text report successfully written to %s at %s", outputFilenameText, timestamp)
	}
}

// formatUserTables renders the ZTA and IG per-user tables for a single cycle.
func formatUserTables(
	ztaMAU map[string]*UserResourceUsage,
	igMAU map[string]*UserIGUsage,
	userKind map[string]UserKindLabel,
) string {
	var output string

	if len(ztaMAU) > 0 {
		output += "ZERO TRUST ACCESS (ZTA MAU) - Resource Usage\n"
		output += "-------------------------------------------------\n"

		maxUserLen := 4
		for user := range ztaMAU {
			if len(user) > maxUserLen {
				maxUserLen = len(user)
			}
		}

		userColWidth := maxUserLen + 2
		kindColWidth := 6

		output += fmt.Sprintf("%-*s  %-*s  %-8s  %-8s  %-8s  %-8s  %-8s  %-8s\n",
			userColWidth, "User",
			kindColWidth, "Kind",
			"Logins", "SSH", "Kube", "DB", "App", "Desktop")

		separatorLen := userColWidth + 2 + kindColWidth + 2 + 8*6 + 2*6
		output += fmt.Sprintf("%s\n", strings.Repeat("-", separatorLen))

		for _, user := range sortedKeys(ztaMAU) {
			usage := ztaMAU[user]
			kind := userKind[user]
			if kind == "" {
				kind = UserKindHuman
			}

			output += fmt.Sprintf("%-*s  %-*s  %-8d  %-8d  %-8d  %-8d  %-8d  %-8d\n",
				userColWidth, user,
				kindColWidth, kind,
				usage.LoginCount, usage.SSH, usage.Kubernetes,
				usage.Database, usage.Application, usage.Desktop)
		}
		output += "\n"
	}

	if len(igMAU) > 0 {
		output += "IDENTITY GOVERNANCE (IG MAU) - Feature Usage\n"
		output += "-------------------------------------------------\n"

		maxUserLen := 4
		for user := range igMAU {
			if len(user) > maxUserLen {
				maxUserLen = len(user)
			}
		}

		userColWidth := maxUserLen + 2
		output += fmt.Sprintf("%-*s  %-12s  %-12s  %-12s  %-12s  %-12s\n",
			userColWidth, "User", "Req Created", "Req Reviewed", "List Member", "List Review", "SAML IdP")

		separatorLen := userColWidth + 2 + 12*5 + 2*5
		output += fmt.Sprintf("%s\n", strings.Repeat("-", separatorLen))

		for _, user := range sortedKeys(igMAU) {
			usage := igMAU[user]
			output += fmt.Sprintf("%-*s  %-12d  %-12d  %-12d  %-12d  %-12d\n",
				userColWidth, user, usage.AccessRequestsCreated, usage.AccessRequestsReviewed,
				usage.AccessListsMemberships, usage.AccessListsReviewed, usage.SAMLIDPSessions)
		}
	}

	return output
}

// cycleLabel returns the human-readable cycle label, suffixed when in progress.
func cycleLabel(c cycleBounds) string {
	if c.InProgress {
		return c.Label + " (in progress)"
	}
	return c.Label
}

// writePerCycleReport emits a billing-cycle-aligned report (text or JSON).
func writePerCycleReport(cycles []cycleBounds, accums []*cycleAccum, summaries []cycleSummary) {
	timestamp := time.Now().Format("2006-01-02 15:04:05")

	if reportFormat == "json" {
		cycleData := make([]map[string]interface{}, len(cycles))
		for i, c := range cycles {
			s := summaries[i]
			cycleData[i] = map[string]interface{}{
				"label":                   c.Label,
				"start":                   c.Start.Format(time.RFC3339),
				"end":                     c.End.Format(time.RFC3339),
				"in_progress":             c.InProgress,
				"total_ztamau_users":      s.ztaHumanCount,
				"total_igmau_users":       s.igHumanCount,
				"total_mwi_bots":          s.mwiBotCount,
				"total_successful_logins": accums[i].totalLogins,
				"user_kind":               accums[i].userKind,
				"zta_resource_usage_all":  s.ztaMAUAll,
				"ig_feature_usage_all":    s.igMAUAll,
			}
		}

		reportData := map[string]interface{}{
			"teleport_proxy_url": teleportProxyURL,
			"timestamp":          timestamp,
			"billing_anchor_day": billingDayAnchor,
			"cycles":             cycleData,
		}

		jsonData, err := json.MarshalIndent(reportData, "", "  ")
		if err != nil {
			log.Fatalf("Failed to generate JSON report: %v", err)
		}

		jsonFile, err := os.OpenFile(outputFilenameJson, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
		if err != nil {
			log.Fatalf("Failed to open JSON report file: %v", err)
		}
		defer jsonFile.Close()

		if _, err := jsonFile.Write(jsonData); err != nil {
			log.Fatalf("Failed to write JSON report: %v", err)
		}
		log.Printf("[INFO] JSON report successfully written to %s at %s", outputFilenameJson, timestamp)
		return
	}

	// Text output
	file, err := os.OpenFile(outputFilenameText, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		log.Fatalf("Failed to open report file: %v", err)
	}
	defer file.Close()

	output := fmt.Sprintf("\n[%s] Teleport Active Users Report (billing cycles)\n", timestamp)
	output += fmt.Sprintf("Teleport Proxy URL: %s\n", teleportProxyURL)
	output += fmt.Sprintf("Billing anchor day: %d\n", billingDayAnchor)
	output += "=================================================\n"

	// Per-cycle summary table.
	labelWidth := len("Cycle")
	for _, c := range cycles {
		if l := len(cycleLabel(c)); l > labelWidth {
			labelWidth = l
		}
	}
	labelWidth += 2
	output += fmt.Sprintf("%-*s  %-8s  %-8s  %-6s  %-8s\n",
		labelWidth, "Cycle", "ZTA MAU", "IG MAU", "MWI", "Logins")
	output += strings.Repeat("-", labelWidth+2+8+2+8+2+6+2+8) + "\n"
	for i, c := range cycles {
		s := summaries[i]
		output += fmt.Sprintf("%-*s  %-8d  %-8d  %-6d  %-8d\n",
			labelWidth, cycleLabel(c),
			s.ztaHumanCount, s.igHumanCount, s.mwiBotCount, accums[i].totalLogins)
	}
	output += "=================================================\n\n"

	// Per-cycle detail tables.
	for i, c := range cycles {
		s := summaries[i]
		output += fmt.Sprintf("--- %s ---\n", cycleLabel(c))
		tables := formatUserTables(s.ztaMAUAll, s.igMAUAll, accums[i].userKind)
		if tables == "" {
			output += "(no activity in this cycle)\n\n"
		} else {
			output += tables + "\n"
		}
	}

	if _, err = file.WriteString(output); err != nil {
		log.Fatalf("Failed to write to report file: %v", err)
	}
	log.Printf("[INFO] Text report successfully written to %s at %s", outputFilenameText, timestamp)
}

// billingDayAnchor mirrors the -billing-day flag so report writers can include
// it without threading an extra argument through.
var billingDayAnchor int
