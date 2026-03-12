package main

import (
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/kevinburke/ssh_config"
	"golang.org/x/crypto/ssh"
)

func (fb *FileBrowser) connectViaProxyJump(proxyJump, targetHost, targetPort string, config *ssh.ClientConfig) (net.Conn, error) {
	proxies := strings.Split(proxyJump, ",")
	if len(proxies) > 1 {
		return nil, fmt.Errorf("multiple ProxyJump hops not yet supported")
	}

	proxyHost := proxies[0]
	var proxyUser, proxyHostname, proxyPort string

	if strings.Contains(proxyHost, "@") {
		parts := strings.Split(proxyHost, "@")
		proxyUser = parts[0]
		proxyHostname = parts[1]
	} else {
		proxyHostname = proxyHost
	}

	if strings.Contains(proxyHostname, ":") {
		parts := strings.Split(proxyHostname, ":")
		proxyHostname = parts[0]
		proxyPort = parts[1]
	} else {
		proxyPort = "22"
	}

	if proxyUser == "" {
		proxyUser = ssh_config.Get(proxyHost, "User")
		if proxyUser == "" {
			proxyUser = config.User
		}
	}

	proxyConfig := &ssh.ClientConfig{
		User:            proxyUser,
		Auth:            config.Auth,
		HostKeyCallback: config.HostKeyCallback,
		Timeout:         config.Timeout,
	}

	proxyClient, err := ssh.Dial("tcp", proxyHostname+":"+proxyPort, proxyConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to proxy %s: %v", proxyHost, err)
	}

	conn, err := proxyClient.Dial("tcp", targetHost+":"+targetPort)
	if err != nil {
		proxyClient.Close()
		return nil, fmt.Errorf("failed to connect through proxy to %s:%s: %v", targetHost, targetPort, err)
	}

	return conn, nil
}

func (fb *FileBrowser) connectViaProxyCommand(proxyCommand, targetHost, targetPort string) (net.Conn, error) {
	command := strings.ReplaceAll(proxyCommand, "%h", targetHost)
	command = strings.ReplaceAll(command, "%p", targetPort)

	user := fb.userEntry.Text
	if user == "" {
		if homeDir, err := os.UserHomeDir(); err == nil {
			user = filepath.Base(homeDir)
		} else {
			user = os.Getenv("USER")
			if user == "" {
				user = "root"
			}
		}
	}
	command = strings.ReplaceAll(command, "%r", user)

	var parts []string
	if strings.Contains(command, `"`) {
		parts = parseQuotedCommand(command)
	} else {
		parts = strings.Fields(command)
	}

	if len(parts) == 0 {
		return nil, fmt.Errorf("empty proxy command")
	}

	cmd := exec.Command(parts[0], parts[1:]...)
	cmd.Env = os.Environ()

	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, fmt.Errorf("failed to create stdin pipe: %v", err)
	}

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		stdin.Close()
		return nil, fmt.Errorf("failed to create stdout pipe: %v", err)
	}

	stderr, err := cmd.StderrPipe()
	if err != nil {
		stdin.Close()
		stdout.Close()
		return nil, fmt.Errorf("failed to create stderr pipe: %v", err)
	}

	if err := cmd.Start(); err != nil {
		stdin.Close()
		stdout.Close()
		stderr.Close()
		return nil, fmt.Errorf("failed to start proxy command '%s': %v", parts[0], err)
	}

	// Drain stderr in background
	go func() {
		buf := make([]byte, 1024)
		for {
			if _, err := stderr.Read(buf); err != nil {
				break
			}
		}
		stderr.Close()
	}()

	return &proxyConn{stdin: stdin, stdout: stdout, stderr: stderr, cmd: cmd}, nil
}

// proxyConn implements net.Conn for ProxyCommand
func (c *proxyConn) Read(b []byte) (int, error)  { return c.stdout.Read(b) }
func (c *proxyConn) Write(b []byte) (int, error) { return c.stdin.Write(b) }

func (c *proxyConn) Close() error {
	c.stdin.Close()
	c.stdout.Close()
	c.stderr.Close()
	if c.cmd.Process != nil {
		c.cmd.Process.Kill()
	}
	c.cmd.Wait()
	return nil
}

func (c *proxyConn) LocalAddr() net.Addr                { return &net.UnixAddr{Name: "proxy", Net: "proxy"} }
func (c *proxyConn) RemoteAddr() net.Addr               { return &net.UnixAddr{Name: "proxy", Net: "proxy"} }
func (c *proxyConn) SetDeadline(t time.Time) error      { return nil }
func (c *proxyConn) SetReadDeadline(t time.Time) error  { return nil }
func (c *proxyConn) SetWriteDeadline(t time.Time) error { return nil }

func parseQuotedCommand(command string) []string {
	var parts []string
	var current strings.Builder
	inQuotes := false
	escaped := false

	for _, char := range command {
		if escaped {
			current.WriteRune(char)
			escaped = false
			continue
		}

		switch char {
		case '\\':
			escaped = true
		case '"':
			inQuotes = !inQuotes
		case ' ', '\t':
			if inQuotes {
				current.WriteRune(char)
			} else if current.Len() > 0 {
				parts = append(parts, current.String())
				current.Reset()
			}
		default:
			current.WriteRune(char)
		}
	}

	if current.Len() > 0 {
		parts = append(parts, current.String())
	}
	return parts
}

func parseQuotedPaths(input string) []string {
	var paths []string
	var current strings.Builder
	inQuotes := false
	quoteChar := rune(0)

	for _, char := range input {
		switch {
		case (char == '"' || char == '\'') && !inQuotes:
			inQuotes = true
			quoteChar = char
		case char == quoteChar && inQuotes:
			inQuotes = false
			quoteChar = 0
			if current.Len() > 0 {
				paths = append(paths, current.String())
				current.Reset()
			}
		case char == ' ' && !inQuotes:
			if current.Len() > 0 {
				paths = append(paths, current.String())
				current.Reset()
			}
		default:
			current.WriteRune(char)
		}
	}

	if current.Len() > 0 {
		paths = append(paths, current.String())
	}
	return paths
}
