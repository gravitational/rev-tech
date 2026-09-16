// Package preflight contains connection sanity checks shared by the mau and tpr
// subcommands: proxy reachability and active-tsh-profile validation. These run
// before any Teleport API client is constructed so that credential problems
// surface as friendly "run: tsh login --proxy ..." messages.
package preflight

import (
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/gravitational/teleport/api/profile"
)

// Proxy ensures proxy has a port (defaults to :443) and verifies
// reachability via the /v1/webapi/find endpoint. Returns the canonical
// host:port form, or an error explaining what went wrong.
func Proxy(proxy string) (string, error) {
	proxy = strings.TrimSpace(proxy)
	if proxy == "" {
		return "", fmt.Errorf("proxy address is empty (use -proxy <host>[:port])")
	}
	if !strings.Contains(proxy, ":") {
		proxy = proxy + ":443"
	}
	url := "https://" + proxy + "/v1/webapi/find"
	cl := &http.Client{Timeout: 5 * time.Second}
	resp, err := cl.Get(url)
	if err != nil {
		return "", fmt.Errorf("could not reach %s: %w", url, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("could not reach %s: HTTP %d", url, resp.StatusCode)
	}
	return proxy, nil
}

// TshProfile verifies that the active tsh profile in ~/.tsh points
// at proxyURL and has a non-expired certificate.
func TshProfile(proxyURL string) error {
	home, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("could not determine home directory: %w", err)
	}
	dir := filepath.Join(home, ".tsh")

	name, err := profile.GetCurrentProfileName(dir)
	if err != nil {
		return fmt.Errorf("no active tsh profile found in %s — run: tsh login --proxy %s", dir, proxyURL)
	}

	p, err := profile.FromDir(dir, name)
	if err != nil {
		return fmt.Errorf("could not load tsh profile %q: %v — run: tsh login --proxy %s", name, err, proxyURL)
	}

	if p.WebProxyAddr != proxyURL {
		return fmt.Errorf("active tsh profile is for %s, not %s — run: tsh login --proxy %s",
			p.WebProxyAddr, proxyURL, proxyURL)
	}

	expiry, ok := p.Expiry()
	if !ok {
		return fmt.Errorf("could not determine tsh profile expiry for %s — run: tsh login --proxy %s", proxyURL, proxyURL)
	}
	if time.Now().After(expiry) {
		return fmt.Errorf("tsh profile for %s expired at %s — run: tsh login --proxy %s",
			proxyURL, expiry.Format(time.RFC3339), proxyURL)
	}
	return nil
}
