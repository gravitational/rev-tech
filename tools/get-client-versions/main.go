// client_versions extracts tsh client version info from cert.create and
// user.login audit events over the last N days.
package main

import (
	"context"
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
	apievents "github.com/gravitational/teleport/api/types/events"
)

const pageSize = 500

type record struct {
	eventType string
	time      time.Time
	user      string
	userAgent string
}

type latestVersion struct {
	version string
	time    time.Time
	source  string
}

func printRecord(r record) {
	fmt.Printf("event=%-15s time=%-30s user=%-30s user_agent=%s\n",
		r.eventType,
		r.time.Format(time.RFC3339),
		r.user,
		r.userAgent,
	)
}

func updateLatest(m map[string]latestVersion, user, userAgent string, t time.Time, source string) {
	// Extract just the tsh/x.y.z token from the user agent string.
	version := userAgent
	for _, part := range strings.Fields(userAgent) {
		if strings.HasPrefix(part, "tsh/") {
			version = part
			break
		}
	}
	if cur, ok := m[user]; !ok || t.After(cur.time) {
		m[user] = latestVersion{version: version, time: t, source: source}
	}
}

func main() {
	proxy := flag.String("proxy", "", "Teleport proxy address (e.g. proxy.example.com:443)")
	days := flag.Int("days", 90, "Number of days to look back in the audit log")
	verbose := flag.Bool("verbose", false, "Print each matching event as it is found")
	flag.Parse()

	if *proxy == "" {
		log.Fatal("--proxy is required")
	}
	if *days <= 0 {
		log.Fatal("--days must be a positive integer")
	}

	ctx := context.Background()

	clt, err := client.New(ctx, client.Config{
		Addrs: []string{*proxy},
		Credentials: []client.Credentials{
			client.LoadProfile("", ""),
		},
	})
	if err != nil {
		log.Fatalf("failed to create client: %v", err)
	}
	defer clt.Close()

	from := time.Now().UTC().AddDate(0, 0, -*days)
	to := time.Now().UTC()

	fmt.Fprintf(os.Stderr, "Searching audit events from %s to %s...\n",
		from.Format(time.DateOnly), to.Format(time.DateOnly))

	var (
		nextKey     string
		records     []record
		latest      = map[string]latestVersion{}
		total       int
		page        int
		lastEvtTime time.Time
	)

	for {
		evts, key, err := clt.SearchEvents(
			ctx,
			from,
			to,
			defaults.Namespace,
			[]string{"cert.create", "user.login"},
			pageSize,
			types.EventOrderAscending,
			nextKey,
		)
		if err != nil {
			log.Fatalf("SearchEvents error: %v", err)
		}

		page++
		total += len(evts)
		if len(evts) > 0 {
			lastEvtTime = evts[len(evts)-1].GetTime()
		}
		fmt.Fprintf(os.Stderr, "  page %-4d  scanned %-6d  matched %-6d  latest event date %s\n",
			page, total, len(records), lastEvtTime.Format(time.DateOnly))

		for _, evt := range evts {
			switch e := evt.(type) {
			case *apievents.CertificateCreate:
				if e.Identity == nil {
					continue
				}
				if e.Identity.BotName != "" || e.Identity.BotInstanceID != "" || strings.HasPrefix(e.Identity.User, "bot-") {
					continue
				}
				if e.ClientMetadata.UserAgent == "" {
					continue
				}
				r := record{
					eventType: "cert.create",
					time:      e.GetTime(),
					user:      e.Identity.User,
					userAgent: e.ClientMetadata.UserAgent,
				}
				records = append(records, r)
				if *verbose {
					printRecord(r)
				}
				if strings.HasPrefix(e.ClientMetadata.UserAgent, "tsh/") {
					updateLatest(latest, e.Identity.User, e.ClientMetadata.UserAgent, e.GetTime(), "cert.create")
				}

			case *apievents.UserLogin:
				if e.ClientMetadata.UserAgent == "" {
					continue
				}
				r := record{
					eventType: "user.login",
					time:      e.GetTime(),
					user:      e.User,
					userAgent: e.ClientMetadata.UserAgent,
				}
				records = append(records, r)
				if *verbose {
					printRecord(r)
				}
				if strings.HasPrefix(e.ClientMetadata.UserAgent, "tsh/") {
					updateLatest(latest, e.User, e.ClientMetadata.UserAgent, e.GetTime(), "user.login")
				}
			}
		}

		if key == "" {
			break
		}
		nextKey = key
	}

	fmt.Fprintf(os.Stderr, "Done.\n\n")
	fmt.Fprintf(os.Stderr, "%d records total.\n", len(records))

	if len(latest) > 0 {
		fmt.Println("\n--- Latest tsh version per user ---")
		users := make([]string, 0, len(latest))
		for u := range latest {
			users = append(users, u)
		}
		sort.Strings(users)
		for _, u := range users {
			l := latest[u]
			fmt.Printf("  %-30s  %-20s  last seen %-30s  via %s\n",
				u, l.version, l.time.Format(time.RFC3339), l.source)
		}
	}
}
