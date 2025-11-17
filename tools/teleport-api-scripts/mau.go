package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/gravitational/teleport/api/client"
	"github.com/gravitational/teleport/api/defaults"
	"github.com/gravitational/teleport/api/types"
)

// Configuration Variables - Modify these to customize the script behavior
var (
	// Teleport cluster configuration
	teleportProxyURL = "proxy.example.com:443" // Change to your Teleport proxy URL
	useIdentityFile  = false                   // Set to true to use identity file authentication
	identityFilePath = "/path/to/identity"     // Path to identity file (only used if useIdentityFile = true)

	// Time range configuration
	daysBack = 30 // Number of days back to analyze (default: 30 days)

	// Report configuration
	reportFormat = "text" // Options: "json" or "text"

	// Performance configuration
	batchSize = 5000 // Number of events to fetch per batch
)

// The main function connects to a Teleport cluster and retrieves user activity events
// within a specified time range. It processes events to track:
// - Zero Trust Access MAU (ZTAMAU): Users accessing protected resources
// - Identity Governance MAU (IGMAU): Users using access request/review features
// - Detailed resource usage breakdown per user
// Events are fetched in paginated batches to optimize retrieval.
// All configuration options can be modified in the variables section above.

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

func main() {
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
	totalLogins := 0
	nextKey := ""

	// Event types to track for both ZTAMAU and IGMAU
	eventTypes := []string{
		// ZTAMAU events (resource access)
		"user.login",
		"session.start",
		"db.session.start",
		"app.session.start",
		"windows.desktop.session.start",
		"kube.request",
		// IGMAU events (identity governance)
		"access_request.create",
		"access_request.review",
		"access_list.member.create",
		"access_list.member.update",
		"access_list.review",
		"saml.idp.auth",
	}

	for {
		log.Println("Fetching batch of events...")
		rawEvents, newNextKey, err := clt.SearchEvents(ctx, fromUTC, toUTC, defaults.Namespace, eventTypes, batchSize, types.EventOrderDescending, nextKey)
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
			if !ok {
				continue
			}

			eventType, ok := raw["event"].(string)
			if !ok {
				continue
			}

			// Process ZTAMAU events (resource access)
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

			// Process IGMAU events (identity governance)
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

	// Filter ZTAMAU users who have actually used resources (not just logged in)
	ztaMAU := make(map[string]*UserResourceUsage)
	for user, usage := range userResourceUsage {
		if usage.SSH > 0 || usage.Kubernetes > 0 || usage.Database > 0 || usage.Application > 0 || usage.Desktop > 0 {
			ztaMAU[user] = usage
		}
	}

	// Filter IGMAU users who have used identity governance features
	igMAU := make(map[string]*UserIGUsage)
	for user, usage := range userIGUsage {
		if usage.AccessRequestsCreated > 0 || usage.AccessRequestsReviewed > 0 ||
			usage.AccessListsMemberships > 0 || usage.AccessListsReviewed > 0 ||
			usage.SAMLIDPSessions > 0 {
			igMAU[user] = usage
		}
	}

	// Write report to file based on selected format
	writeUserReport(ztaMAU, igMAU, totalLogins)
}

// Writes the user activity report to a file in either JSON or text format
func writeUserReport(ztaMAU map[string]*UserResourceUsage, igMAU map[string]*UserIGUsage, totalLogins int) {
	timestamp := time.Now().Format("2006-01-02 15:04:05")

	if reportFormat == "json" {
		// JSON Output
		reportData := map[string]interface{}{
			"timestamp":               timestamp,
			"total_ztamau":            len(ztaMAU),
			"total_igmau":             len(igMAU),
			"total_successful_logins": totalLogins,
			"zta_resource_usage":      ztaMAU,
			"ig_feature_usage":        igMAU,
		}

		jsonData, err := json.MarshalIndent(reportData, "", "  ")
		if err != nil {
			log.Fatalf("Failed to generate JSON report: %v", err)
		}

		// Write JSON report to file
		jsonFile, err := os.OpenFile("Teleport_Active_Users.json", os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
		if err != nil {
			log.Fatalf("Failed to open JSON report file: %v", err)
		}
		defer jsonFile.Close()

		_, err = jsonFile.Write(jsonData)
		if err != nil {
			log.Fatalf("Failed to write JSON report: %v", err)
		}

		log.Printf("[INFO] JSON report successfully written at %s", timestamp)

	} else {
		// Default Text Output
		file, err := os.OpenFile("Teleport_Active_Users.txt", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
		if err != nil {
			log.Fatalf("Failed to open report file: %v", err)
		}
		defer file.Close()

		// Generate report header
		output := fmt.Sprintf("\n[%s] Teleport Active Users Report\n", timestamp)
		output += "=================================================\n"
		output += fmt.Sprintf("Total Zero Trust Access MAU (ZTAMAU): %d\n", len(ztaMAU))
		output += fmt.Sprintf("Total Identity Governance MAU (IGMAU): %d\n", len(igMAU))
		output += fmt.Sprintf("Total Successful Logins: %d\n", totalLogins)
		output += "=================================================\n\n"

		// ZTAMAU Report Section
		if len(ztaMAU) > 0 {
			output += "ZERO TRUST ACCESS (ZTAMAU) - Resource Usage\n"
			output += "-------------------------------------------------\n"

			// Calculate max username length for ZTAMAU
			maxUserLen := 4
			for user := range ztaMAU {
				if len(user) > maxUserLen {
					maxUserLen = len(user)
				}
			}

			userColWidth := maxUserLen + 2
			output += fmt.Sprintf("%-*s  %-8s  %-8s  %-8s  %-8s  %-8s  %-8s\n",
				userColWidth, "User", "Logins", "SSH", "Kube", "DB", "App", "Desktop")

			separatorLen := userColWidth + 2 + 8*6 + 2*6
			output += fmt.Sprintf("%s\n", strings.Repeat("-", separatorLen))

			for user, usage := range ztaMAU {
				output += fmt.Sprintf("%-*s  %-8d  %-8d  %-8d  %-8d  %-8d  %-8d\n",
					userColWidth, user, usage.LoginCount, usage.SSH, usage.Kubernetes,
					usage.Database, usage.Application, usage.Desktop)
			}
			output += "\n"
		}

		// IGMAU Report Section
		if len(igMAU) > 0 {
			output += "IDENTITY GOVERNANCE (IGMAU) - Feature Usage\n"
			output += "-------------------------------------------------\n"

			// Calculate max username length for IGMAU
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

			for user, usage := range igMAU {
				output += fmt.Sprintf("%-*s  %-12d  %-12d  %-12d  %-12d  %-12d\n",
					userColWidth, user, usage.AccessRequestsCreated, usage.AccessRequestsReviewed,
					usage.AccessListsMemberships, usage.AccessListsReviewed, usage.SAMLIDPSessions)
			}
		}

		_, err = file.WriteString(output)
		if err != nil {
			log.Fatalf("Failed to write to report file: %v", err)
		}

		log.Printf("[INFO] Text report successfully written at %s", timestamp)
	}
}
