// Package mau implements the Monthly Active Users report: a one-shot pass over
// the last N days of Teleport audit events (or aligned to billing cycles when
// BillingDay is set), classifying activity into Zero Trust Access (ZTA) and
// Identity Governance (IG) buckets and writing a text or JSON report.
package mau

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/gravitational/teleport/api/defaults"
	"github.com/gravitational/teleport/api/types"

	"github.com/jturner-teleport/teleport-usage/internal/cycles"
	"github.com/jturner-teleport/teleport-usage/internal/preflight"
	"github.com/jturner-teleport/teleport-usage/internal/teleportclient"
)

// Options carries the resolved configuration for a single mau run. Fields that
// were package-level vars in the original program now live here.
type Options struct {
	// ProxyAddr is the Teleport proxy address (required; e.g. host:443).
	ProxyAddr string
	// IdentityFile, when non-empty, authenticates with an exported identity
	// file instead of the ambient tsh profile.
	IdentityFile string
	// Format is "text" or "json".
	Format string
	// BillingDay is the billing-cycle anchor day (1-31), or 0 to use the
	// rolling DaysBack window.
	BillingDay int
	// Cycles is the number of completed cycles to include alongside the
	// in-progress cycle (only used with BillingDay).
	Cycles int

	// DaysBack is the rolling look-back window when BillingDay is 0.
	DaysBack int
	// BatchSize is the number of events to fetch per SearchEvents page.
	BatchSize int
	// OutputFilenameText / OutputFilenameJSON are the report output paths.
	OutputFilenameText string
	OutputFilenameJSON string
}

// DefaultOptions returns Options populated with the original program's tunable
// defaults (daysBack, batchSize, output filenames).
func DefaultOptions() Options {
	return Options{
		Format:             "text",
		Cycles:             3,
		DaysBack:           30,
		BatchSize:          5000,
		OutputFilenameText: "Teleport_Active_Users.txt",
		OutputFilenameJSON: "Teleport_Active_Users.json",
	}
}

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

// Run executes the MAU report against the cluster described by o. It performs
// preflight checks, connects to Teleport, pages through audit events, and
// writes the report. It mirrors the original teleport-mau-tracker behavior.
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

	clt, err := teleportclient.Connect(ctx, o.ProxyAddr, o.IdentityFile)
	if err != nil {
		return fmt.Errorf("failed to create client: %w", err)
	}
	defer clt.Close()

	// Define the time range and per-cycle accumulators.
	var (
		fromUTC, toUTC time.Time
		cycleList      []cycles.Bounds
		accums         []*cycleAccum
		single         *cycleAccum
	)
	if o.BillingDay > 0 {
		now := time.Now().UTC()
		cycleList = cycles.LastN(now, o.BillingDay, o.Cycles)
		accums = make([]*cycleAccum, len(cycleList))
		for i := range accums {
			accums[i] = newCycleAccum()
		}
		fromUTC = cycleList[0].Start
		toUTC = now
		log.Printf("[INFO] Billing-cycle mode: anchor=%d, %d cycle(s) from %s to %s",
			o.BillingDay, len(cycleList), fromUTC.Format("2006-01-02"), toUTC.Format("2006-01-02"))
		if now.Sub(fromUTC) > 90*24*time.Hour {
			log.Printf("[WARN] Requested window spans %.0f days; older cycles may be empty due to audit log retention.",
				now.Sub(fromUTC).Hours()/24)
		}
	} else {
		fromUTC = time.Now().AddDate(0, 0, -o.DaysBack)
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
			o.BatchSize,
			types.EventOrderDescending,
			nextKey,
		)
		if err != nil {
			return fmt.Errorf("Failed to fetch events: %w", err)
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

			if o.BillingDay > 0 {
				et := event.GetTime().UTC()
				idx := -1
				for i, c := range cycleList {
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

	if o.BillingDay > 0 {
		summaries := make([]cycleSummary, len(cycleList))
		for i, a := range accums {
			summaries[i] = a.summarize()
		}
		if err := writePerCycleReport(o, cycleList, accums, summaries); err != nil {
			return err
		}
	} else {
		s := single.summarize()
		if err := writeUserReport(o, s.ztaMAUAll, s.igMAUAll, single.userKind, single.totalLogins, s.ztaHumanCount, s.igHumanCount, s.mwiBotCount); err != nil {
			return err
		}
	}
	return nil
}

// Writes the user activity report to a file in either JSON or text format
func writeUserReport(
	o Options,
	ztaMAU map[string]*UserResourceUsage,
	igMAU map[string]*UserIGUsage,
	userKind map[string]UserKindLabel,
	totalLogins int,
	ztaHumanCount int,
	igHumanCount int,
	mwiBotCount int,
) error {
	timestamp := time.Now().Format("2006-01-02 15:04:05")

	if o.Format == "json" {
		// JSON Output
		reportData := map[string]interface{}{
			"teleport_proxy_url":      o.ProxyAddr,
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
			return fmt.Errorf("Failed to generate JSON report: %w", err)
		}

		// Write JSON report to file
		jsonFile, err := os.OpenFile(o.OutputFilenameJSON, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
		if err != nil {
			return fmt.Errorf("Failed to open JSON report file: %w", err)
		}
		defer jsonFile.Close()

		_, err = jsonFile.Write(jsonData)
		if err != nil {
			return fmt.Errorf("Failed to write JSON report: %w", err)
		}

		log.Printf("[INFO] JSON report successfully written to %s at %s", o.OutputFilenameJSON, timestamp)

	} else {
		// Default Text Output
		file, err := os.OpenFile(o.OutputFilenameText, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
		if err != nil {
			return fmt.Errorf("Failed to open report file: %w", err)
		}
		defer file.Close()

		// Generate report header
		output := fmt.Sprintf("\n[%s] Teleport Active Users Report\n", timestamp)
		output += fmt.Sprintf("Teleport Proxy URL: %s\n", o.ProxyAddr)
		output += "=================================================\n"
		output += fmt.Sprintf("Total Zero Trust Access MAU (ZTA MAU): %d\n", ztaHumanCount)
		output += fmt.Sprintf("Total Identity Governance MAU (IG MAU): %d\n", igHumanCount)
		output += fmt.Sprintf("Total Machine and Workload Identity Bot users (MWI): %d\n", mwiBotCount)
		output += fmt.Sprintf("Total Successful Logins: %d\n", totalLogins)
		output += "=================================================\n\n"

		output += formatUserTables(ztaMAU, igMAU, userKind)

		_, err = file.WriteString(output)
		if err != nil {
			return fmt.Errorf("Failed to write to report file: %w", err)
		}

		log.Printf("[INFO] Text report successfully written to %s at %s", o.OutputFilenameText, timestamp)
	}
	return nil
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
func cycleLabel(c cycles.Bounds) string {
	if c.InProgress {
		return c.Label + " (in progress)"
	}
	return c.Label
}

// writePerCycleReport emits a billing-cycle-aligned report (text or JSON).
func writePerCycleReport(o Options, cycleList []cycles.Bounds, accums []*cycleAccum, summaries []cycleSummary) error {
	timestamp := time.Now().Format("2006-01-02 15:04:05")

	if o.Format == "json" {
		cycleData := make([]map[string]interface{}, len(cycleList))
		for i, c := range cycleList {
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
			"teleport_proxy_url": o.ProxyAddr,
			"timestamp":          timestamp,
			"billing_anchor_day": o.BillingDay,
			"cycles":             cycleData,
		}

		jsonData, err := json.MarshalIndent(reportData, "", "  ")
		if err != nil {
			return fmt.Errorf("Failed to generate JSON report: %w", err)
		}

		jsonFile, err := os.OpenFile(o.OutputFilenameJSON, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
		if err != nil {
			return fmt.Errorf("Failed to open JSON report file: %w", err)
		}
		defer jsonFile.Close()

		if _, err := jsonFile.Write(jsonData); err != nil {
			return fmt.Errorf("Failed to write JSON report: %w", err)
		}
		log.Printf("[INFO] JSON report successfully written to %s at %s", o.OutputFilenameJSON, timestamp)
		return nil
	}

	// Text output
	file, err := os.OpenFile(o.OutputFilenameText, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		return fmt.Errorf("Failed to open report file: %w", err)
	}
	defer file.Close()

	output := fmt.Sprintf("\n[%s] Teleport Active Users Report (billing cycles)\n", timestamp)
	output += fmt.Sprintf("Teleport Proxy URL: %s\n", o.ProxyAddr)
	output += fmt.Sprintf("Billing anchor day: %d\n", o.BillingDay)
	output += "=================================================\n"

	// Per-cycle summary table.
	labelWidth := len("Cycle")
	for _, c := range cycleList {
		if l := len(cycleLabel(c)); l > labelWidth {
			labelWidth = l
		}
	}
	labelWidth += 2
	output += fmt.Sprintf("%-*s  %-8s  %-8s  %-6s  %-8s\n",
		labelWidth, "Cycle", "ZTA MAU", "IG MAU", "MWI", "Logins")
	output += strings.Repeat("-", labelWidth+2+8+2+8+2+6+2+8) + "\n"
	for i, c := range cycleList {
		s := summaries[i]
		output += fmt.Sprintf("%-*s  %-8d  %-8d  %-6d  %-8d\n",
			labelWidth, cycleLabel(c),
			s.ztaHumanCount, s.igHumanCount, s.mwiBotCount, accums[i].totalLogins)
	}
	output += "=================================================\n\n"

	// Per-cycle detail tables.
	for i, c := range cycleList {
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
		return fmt.Errorf("Failed to write to report file: %w", err)
	}
	log.Printf("[INFO] Text report successfully written to %s at %s", o.OutputFilenameText, timestamp)
	return nil
}
