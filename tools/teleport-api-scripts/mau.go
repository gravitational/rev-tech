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

	// Define the time range based on configuration
	fromUTC := time.Now().AddDate(0, 0, -daysBack)
	toUTC := time.Now()

	userResourceUsage := make(map[string]*UserResourceUsage)
	userIGUsage := make(map[string]*UserIGUsage)

	// Track per-user kind (Human/Bot) based on events
	userKind := make(map[string]UserKindLabel)

	totalLogins := 0
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

			user, ok := raw["user"].(string)
			if !ok || user == "" {
				continue
			}

			// Track kind (prefer Bot if we ever see Bot for that username)
			kind := classifyUserKind(raw)
			if existing, ok := userKind[user]; !ok {
				userKind[user] = kind
			} else if existing != UserKindBot && kind == UserKindBot {
				userKind[user] = UserKindBot
			}

			eventType, ok := raw["event"].(string)
			if !ok {
				continue
			}

			// Process ZTA MAU events (resource access)
			switch eventType {
			case "user.login":
				if userResourceUsage[user] == nil {
					userResourceUsage[user] = &UserResourceUsage{}
				}
				if raw["success"] == true {
					userResourceUsage[user].LoginCount++
					totalLogins++
				}
			case "session.start":
				if userResourceUsage[user] == nil {
					userResourceUsage[user] = &UserResourceUsage{}
				}
				// Check if this is a kubernetes session by looking for kubernetes_cluster field
				if kubeCluster, exists := raw["kubernetes_cluster"]; exists && kubeCluster != nil {
					userResourceUsage[user].Kubernetes++
				} else {
					userResourceUsage[user].SSH++
				}
			case "db.session.start":
				if userResourceUsage[user] == nil {
					userResourceUsage[user] = &UserResourceUsage{}
				}
				userResourceUsage[user].Database++
			case "app.session.start":
				if userResourceUsage[user] == nil {
					userResourceUsage[user] = &UserResourceUsage{}
				}
				userResourceUsage[user].Application++
			case "windows.desktop.session.start":
				if userResourceUsage[user] == nil {
					userResourceUsage[user] = &UserResourceUsage{}
				}
				userResourceUsage[user].Desktop++
			case "kube.request":
				if userResourceUsage[user] == nil {
					userResourceUsage[user] = &UserResourceUsage{}
				}
				userResourceUsage[user].Kubernetes++
			}

			// Process IG MAU events (identity governance)
			switch eventType {
			case "access_request.create":
				if userIGUsage[user] == nil {
					userIGUsage[user] = &UserIGUsage{}
				}
				userIGUsage[user].AccessRequestsCreated++
			case "access_request.review":
				// For reviews, the reviewer is in the "user" field
				if userIGUsage[user] == nil {
					userIGUsage[user] = &UserIGUsage{}
				}
				userIGUsage[user].AccessRequestsReviewed++
			case "access_list.member.create", "access_list.member.update":
				// Track when users get roles assigned through access list membership
				if userIGUsage[user] == nil {
					userIGUsage[user] = &UserIGUsage{}
				}
				userIGUsage[user].AccessListsMemberships++
			case "access_list.review":
				// Track when users review access lists
				if userIGUsage[user] == nil {
					userIGUsage[user] = &UserIGUsage{}
				}
				userIGUsage[user].AccessListsReviewed++
			case "saml.idp.auth":
				// Track SAML IdP sessions
				if userIGUsage[user] == nil {
					userIGUsage[user] = &UserIGUsage{}
				}
				userIGUsage[user].SAMLIDPSessions++
			}
		}

		// If no next page, break
		if newNextKey == "" || newNextKey == nextKey {
			break
		}
		nextKey = newNextKey
	}

	// Filter ZTA MAU users who have actually used resources (not just logged in)
	ztaMAUAll := make(map[string]*UserResourceUsage)
	for user, usage := range userResourceUsage {
		if usage.SSH > 0 || usage.Kubernetes > 0 || usage.Database > 0 || usage.Application > 0 || usage.Desktop > 0 {
			ztaMAUAll[user] = usage
		}
	}

	// Filter IG MAU users who have used identity governance features
	igMAUAll := make(map[string]*UserIGUsage)
	for user, usage := range userIGUsage {
		if usage.AccessRequestsCreated > 0 || usage.AccessRequestsReviewed > 0 ||
			usage.AccessListsMemberships > 0 || usage.AccessListsReviewed > 0 ||
			usage.SAMLIDPSessions > 0 {
			igMAUAll[user] = usage
		}
	}

	// Compute totals:
	// - ZTA MAU (humans only)
	// - IG MAU (humans only)
	// - MWI (bots only) = unique bot users across either ZTA/IG activity
	ztaHumanCount := 0
	igHumanCount := 0
	botSet := make(map[string]struct{})

	for user := range ztaMAUAll {
		if userKind[user] == UserKindBot {
			botSet[user] = struct{}{}
		} else {
			ztaHumanCount++
		}
	}
	for user := range igMAUAll {
		if userKind[user] == UserKindBot {
			botSet[user] = struct{}{}
		} else {
			igHumanCount++
		}
	}
	mwiBotCount := len(botSet)

	// Write report to file based on selected format
	writeUserReport(ztaMAUAll, igMAUAll, userKind, totalLogins, ztaHumanCount, igHumanCount, mwiBotCount)
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

		// ZTA MAU Report Section (includes both humans & bots)
		if len(ztaMAU) > 0 {
			output += "ZERO TRUST ACCESS (ZTA MAU) - Resource Usage\n"
			output += "-------------------------------------------------\n"

			// Calculate max username length for ZTA MAU
			maxUserLen := 4
			for user := range ztaMAU {
				if len(user) > maxUserLen {
					maxUserLen = len(user)
				}
			}

			userColWidth := maxUserLen + 2
			kindColWidth := 6 // Needs to fit "Human" or "Bot"

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

		// IG MAU Report Section
		if len(igMAU) > 0 {
			output += "IDENTITY GOVERNANCE (IG MAU) - Feature Usage\n"
			output += "-------------------------------------------------\n"

			// Calculate max username length for IG MAU
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

		_, err = file.WriteString(output)
		if err != nil {
			log.Fatalf("Failed to write to report file: %v", err)
		}

		log.Printf("[INFO] Text report successfully written to %s at %s", outputFilenameText, timestamp)
	}
}
