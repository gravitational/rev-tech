package main

import (
	"encoding/base64"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"

	"fyne.io/fyne/v2/dialog"
	"github.com/kevinburke/ssh_config"
	"golang.org/x/crypto/ssh"
)

type knownKey struct {
	pattern  string
	key      ssh.PublicKey
	filePath string
}

func (fb *FileBrowser) getKnownHostsCallback(configHost, targetHost, targetPort string) (ssh.HostKeyCallback, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return nil, fmt.Errorf("failed to get home directory: %v", err)
	}

	knownHostsFiles := fb.getKnownHostsFiles(configHost, homeDir)
	defaultKnownHosts := filepath.Join(homeDir, ".ssh", "known_hosts")

	// Ensure default known_hosts exists
	if _, err := os.Stat(defaultKnownHosts); os.IsNotExist(err) {
		sshDir := filepath.Join(homeDir, ".ssh")
		os.MkdirAll(sshDir, 0700)
		os.WriteFile(defaultKnownHosts, []byte{}, 0600)
	}

	knownKeys := fb.loadKnownKeys(knownHostsFiles)

	return func(hostname string, remote net.Addr, key ssh.PublicKey) error {
		keyFingerprint := ssh.FingerprintSHA256(key)
		hostsToCheck := fb.buildHostsToCheck(configHost, targetHost, targetPort, hostname)

		fmt.Printf("DEBUG: Checking host keys for hosts: %v\n", hostsToCheck)

		// Check for matching keys
		for _, kk := range knownKeys {
			for _, hostCheck := range hostsToCheck {
				if matchHost(kk.pattern, hostCheck) {
					fmt.Printf("DEBUG: Pattern '%s' matched host '%s'\n", kk.pattern, hostCheck)
					if ssh.FingerprintSHA256(kk.key) == keyFingerprint {
						fmt.Printf("DEBUG: Key matched!\n")
						return nil
					}
				}
			}
		}

		// Check if any pattern matched (may be cert-authority)
		for _, kk := range knownKeys {
			for _, hostCheck := range hostsToCheck {
				if matchHost(kk.pattern, hostCheck) {
					fmt.Printf("DEBUG: Found matching pattern '%s', accepting\n", kk.pattern)
					return nil
				}
			}
		}

		fmt.Printf("DEBUG: No matching host key found\n")

		// Unknown host - prompt user
		if fb.promptHostKeyAcceptance(targetHost, key.Type(), keyFingerprint, defaultKnownHosts) {
			if err := fb.addHostKey(defaultKnownHosts, targetHost, key); err != nil {
				return fmt.Errorf("failed to add host key: %v", err)
			}
			return nil
		}
		return fmt.Errorf("host key verification rejected by user")
	}, nil
}

func (fb *FileBrowser) getKnownHostsFiles(configHost, homeDir string) []string {
	var files []string

	userKnownHosts := ssh_config.Get(configHost, "UserKnownHostsFile")
	if userKnownHosts != "" {
		for _, f := range parseQuotedPaths(userKnownHosts) {
			f = strings.Trim(f, "\"'")
			if strings.HasPrefix(f, "~/") {
				f = filepath.Join(homeDir, f[2:])
			} else if strings.HasPrefix(f, "~") {
				f = filepath.Join(homeDir, f[1:])
			}
			files = append(files, f)
		}
	}

	files = append(files, filepath.Join(homeDir, ".ssh", "known_hosts"))

	if _, err := os.Stat("/etc/ssh/ssh_known_hosts"); err == nil {
		files = append(files, "/etc/ssh/ssh_known_hosts")
	}

	return files
}

func (fb *FileBrowser) loadKnownKeys(files []string) []knownKey {
	var keys []knownKey

	for _, path := range files {
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}

		for _, line := range strings.Split(string(data), "\n") {
			line = strings.TrimSpace(line)
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}

			if strings.HasPrefix(line, "@cert-authority ") {
				line = strings.TrimPrefix(line, "@cert-authority ")
			} else if strings.HasPrefix(line, "@revoked ") {
				continue
			}

			fields := strings.Fields(line)
			if len(fields) < 3 {
				continue
			}

			keyBytes := []byte(fields[1] + " " + fields[2])
			pubKey, _, _, _, err := ssh.ParseAuthorizedKey(keyBytes)
			if err != nil {
				continue
			}

			for _, h := range strings.Split(fields[0], ",") {
				if strings.HasPrefix(h, "|1|") {
					continue // Skip hashed hostnames
				}

				origHost := h
				h = strings.TrimPrefix(h, "[")
				if idx := strings.Index(h, "]:"); idx != -1 {
					h = h[:idx] + ":" + h[idx+2:]
				} else {
					h = strings.TrimSuffix(h, "]")
				}

				keys = append(keys, knownKey{pattern: h, key: pubKey, filePath: path})
				if origHost != h {
					keys = append(keys, knownKey{pattern: origHost, key: pubKey, filePath: path})
				}
			}
		}
	}

	return keys
}

func (fb *FileBrowser) buildHostsToCheck(configHost, targetHost, targetPort, hostname string) []string {
	hosts := []string{targetHost}

	if targetPort != "" && targetPort != "22" {
		hosts = append(hosts, fmt.Sprintf("%s:%s", targetHost, targetPort))
		hosts = append(hosts, fmt.Sprintf("[%s]:%s", targetHost, targetPort))
	}

	if configHost != targetHost {
		hosts = append(hosts, configHost)
	}

	if hostname != targetHost && hostname != configHost {
		hosts = append(hosts, hostname)
		if h, _, err := net.SplitHostPort(hostname); err == nil {
			hosts = append(hosts, h)
		}
	}

	return hosts
}

func matchHost(pattern, hostname string) bool {
	if strings.HasPrefix(pattern, "!") {
		return false
	}
	if pattern == hostname {
		return true
	}
	if !strings.Contains(pattern, "*") && !strings.Contains(pattern, "?") {
		return false
	}

	// Simple glob matching
	patternIdx, hostnameIdx := 0, 0
	starIdx, matchIdx := -1, 0

	for hostnameIdx < len(hostname) {
		if patternIdx < len(pattern) && (pattern[patternIdx] == '?' || pattern[patternIdx] == hostname[hostnameIdx]) {
			patternIdx++
			hostnameIdx++
		} else if patternIdx < len(pattern) && pattern[patternIdx] == '*' {
			starIdx = patternIdx
			matchIdx = hostnameIdx
			patternIdx++
		} else if starIdx != -1 {
			patternIdx = starIdx + 1
			matchIdx++
			hostnameIdx = matchIdx
		} else {
			return false
		}
	}

	for patternIdx < len(pattern) && pattern[patternIdx] == '*' {
		patternIdx++
	}

	return patternIdx == len(pattern)
}

func (fb *FileBrowser) promptHostKeyAcceptance(hostname, keyType, fingerprint, knownHostsPath string) bool {
	resultChan := make(chan bool)

	message := fmt.Sprintf("The authenticity of host '%s' can't be established.\n\n"+
		"Host key type: %s\n"+
		"Host key fingerprint:\n%s\n\n"+
		"Are you sure you want to continue connecting?\n"+
		"The key will be added to:\n%s",
		hostname, keyType, fingerprint, knownHostsPath)

	dialog.ShowConfirm("Unknown Host Key", message, func(accepted bool) {
		resultChan <- accepted
	}, fb.mainWindow)

	return <-resultChan
}

func (fb *FileBrowser) addHostKey(knownHostsPath, hostname string, key ssh.PublicKey) error {
	keyBytes := key.Marshal()
	keyBase64 := base64.StdEncoding.EncodeToString(keyBytes)
	line := fmt.Sprintf("%s %s %s", hostname, key.Type(), keyBase64)

	f, err := os.OpenFile(knownHostsPath, os.O_APPEND|os.O_WRONLY|os.O_CREATE, 0600)
	if err != nil {
		return err
	}
	defer f.Close()

	_, err = f.WriteString(line + "\n")
	return err
}
