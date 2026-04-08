package main

import (
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"

	"fyne.io/fyne/v2/dialog"
	"github.com/kevinburke/ssh_config"
	"github.com/pkg/sftp"
	"golang.org/x/crypto/ssh"
	"golang.org/x/crypto/ssh/agent"
)

func (fb *FileBrowser) connectToSSH() {
	if fb.sshConn.connected {
		fb.disconnectSSH()
		return
	}

	host := fb.hostEntry.Text
	if host == "" {
		dialog.ShowError(fmt.Errorf("please enter a hostname"), fb.mainWindow)
		return
	}

	fb.remoteStatusLabel.SetText("Connecting...")
	fb.connectButton.SetText("Connecting...")

	go func() {
		var sshConfig *ssh.ClientConfig
		var proxyConn net.Conn
		var err error

		if fb.useConfigCheck.Checked {
			sshConfig, proxyConn, err = fb.buildSSHConfigFromFile(host)
		} else {
			sshConfig, proxyConn, err = fb.buildManualSSHConfig(host)
		}

		if err != nil {
			fb.remoteStatusLabel.SetText(fmt.Sprintf("Config error: %v", err))
			fb.connectButton.SetText("Connect")
			return
		}

		var client *ssh.Client
		if proxyConn != nil {
			sshConn, chans, reqs, err := ssh.NewClientConn(proxyConn, host, sshConfig)
			if err != nil {
				proxyConn.Close()
				fb.remoteStatusLabel.SetText(fmt.Sprintf("SSH handshake failed: %v", err))
				fb.connectButton.SetText("Connect")
				return
			}
			client = ssh.NewClient(sshConn, chans, reqs)
		} else {
			hostname := ssh_config.Get(host, "HostName")
			if hostname == "" {
				hostname = host
			}
			port := ssh_config.Get(host, "Port")
			if port == "" {
				port = "22"
			}

			client, err = ssh.Dial("tcp", hostname+":"+port, sshConfig)
			if err != nil {
				fb.remoteStatusLabel.SetText(fmt.Sprintf("Connection failed: %v", err))
				fb.connectButton.SetText("Connect")
				return
			}
		}

		sftpClient, err := sftp.NewClient(client)
		if err != nil {
			client.Close()
			fb.remoteStatusLabel.SetText(fmt.Sprintf("SFTP failed: %v", err))
			fb.connectButton.SetText("Connect")
			return
		}

		fb.sshConn.client = client
		fb.sshConn.sftpClient = sftpClient
		fb.sshConn.host = host
		fb.sshConn.connected = true

		fb.remoteStatusLabel.SetText("Connected to " + host)
		fb.connectButton.SetText("Disconnect")
		fb.terminalBtn.Enable()

		fb.updateSCPButtonState()
		fb.updateDownloadButtonState()

		homeDir, err := fb.getRemoteHomeDir()
		if err != nil || homeDir == "" {
			homeDir = "/"
		}
		fb.RemoteNavigateTo(homeDir)
	}()
}

func (fb *FileBrowser) disconnectSSH() {
	if fb.sshConn.sftpClient != nil {
		fb.sshConn.sftpClient.Close()
	}
	if fb.sshConn.client != nil {
		fb.sshConn.client.Close()
	}

	fb.sshConn.connected = false
	fb.remoteStatusLabel.SetText("Remote: Disconnected")
	fb.connectButton.SetText("Connect")
	fb.terminalBtn.Disable()
	fb.remoteFiles = []RemoteFile{}
	fb.remoteFileList.Refresh()

	fb.selectedRemoteFiles = fb.selectedRemoteFiles[:0]
	fb.updateSCPButtonState()
	fb.updateDownloadButtonState()
}

func (fb *FileBrowser) buildSSHConfigFromFile(host string) (*ssh.ClientConfig, net.Conn, error) {
	hostname := ssh_config.Get(host, "HostName")
	if hostname == "" {
		hostname = host
	}

	port := ssh_config.Get(host, "Port")
	if port == "" {
		port = "22"
	}

	user := ssh_config.Get(host, "User")
	if user == "" {
		user = fb.userEntry.Text
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
	}

	proxyJump := ssh_config.Get(host, "ProxyJump")
	proxyCommand := ssh_config.Get(host, "ProxyCommand")

	authMethods := fb.buildAuthMethods(host)
	if len(authMethods) == 0 {
		return nil, nil, fmt.Errorf("no authentication methods available")
	}

	hostKeyCallback, err := fb.getKnownHostsCallback(host, hostname, port)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to setup host key verification: %v", err)
	}

	config := &ssh.ClientConfig{
		User:            user,
		Auth:            authMethods,
		HostKeyCallback: hostKeyCallback,
		Timeout:         30 * time.Second,
	}

	if proxyJump != "" {
		conn, err := fb.connectViaProxyJump(proxyJump, hostname, port, config)
		if err != nil {
			return nil, nil, fmt.Errorf("ProxyJump failed: %v", err)
		}
		return config, conn, nil
	} else if proxyCommand != "" && proxyCommand != "none" {
		conn, err := fb.connectViaProxyCommand(proxyCommand, hostname, port)
		if err != nil {
			return nil, nil, fmt.Errorf("ProxyCommand failed: %v", err)
		}
		return config, conn, nil
	}

	return config, nil, nil
}

func (fb *FileBrowser) buildManualSSHConfig(host string) (*ssh.ClientConfig, net.Conn, error) {
	user := fb.userEntry.Text
	if user == "" {
		return nil, nil, fmt.Errorf("username is required for manual connection")
	}

	hostname := host
	port := "22"
	if h, p, err := net.SplitHostPort(host); err == nil {
		hostname = h
		port = p
	}

	authMethods := fb.buildAuthMethods(host)
	if len(authMethods) == 0 {
		return nil, nil, fmt.Errorf("no authentication methods available")
	}

	hostKeyCallback, err := fb.getKnownHostsCallback(host, hostname, port)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to setup host key verification: %v", err)
	}

	config := &ssh.ClientConfig{
		User:            user,
		Auth:            authMethods,
		HostKeyCallback: hostKeyCallback,
		Timeout:         30 * time.Second,
	}

	return config, nil, nil
}

func (fb *FileBrowser) buildAuthMethods(host string) []ssh.AuthMethod {
	var authMethods []ssh.AuthMethod

	// SSH agent
	if sshAuthSock := os.Getenv("SSH_AUTH_SOCK"); sshAuthSock != "" {
		if agentConn, err := net.Dial("unix", sshAuthSock); err == nil {
			agentClient := agent.NewClient(agentConn)
			authMethods = append(authMethods, ssh.PublicKeysCallback(agentClient.Signers))
		}
	}

	// Identity files from config
	identityFiles := ssh_config.GetAll(host, "IdentityFile")
	for _, keyPath := range identityFiles {
		if strings.HasPrefix(keyPath, "~/") {
			homeDir, _ := os.UserHomeDir()
			keyPath = filepath.Join(homeDir, keyPath[2:])
		}
		if _, err := os.Stat(keyPath); os.IsNotExist(err) {
			continue
		}
		if key, err := fb.loadPrivateKey(keyPath); err == nil {
			authMethods = append(authMethods, ssh.PublicKeys(key))
		}
	}

	// Default keys if no identity files configured
	if len(identityFiles) == 0 {
		homeDir, _ := os.UserHomeDir()
		defaultKeys := []string{
			filepath.Join(homeDir, ".ssh", "id_rsa"),
			filepath.Join(homeDir, ".ssh", "id_ecdsa"),
			filepath.Join(homeDir, ".ssh", "id_ed25519"),
			filepath.Join(homeDir, ".ssh", "id_dsa"),
		}
		for _, keyPath := range defaultKeys {
			if key, err := fb.loadPrivateKey(keyPath); err == nil {
				authMethods = append(authMethods, ssh.PublicKeys(key))
			}
		}
	}

	// Manual key entry
	if fb.keyEntry.Text != "" {
		if key, err := fb.loadPrivateKey(fb.keyEntry.Text); err == nil {
			authMethods = append(authMethods, ssh.PublicKeys(key))
		}
	}

	// Password
	if fb.passEntry.Text != "" {
		authMethods = append(authMethods, ssh.Password(fb.passEntry.Text))
	}

	// Keyboard interactive
	authMethods = append(authMethods, ssh.KeyboardInteractive(func(user, instruction string, questions []string, echos []bool) ([]string, error) {
		if len(questions) == 1 && strings.Contains(strings.ToLower(questions[0]), "password") && fb.passEntry.Text != "" {
			return []string{fb.passEntry.Text}, nil
		}
		return nil, fmt.Errorf("interactive authentication not supported")
	}))

	return authMethods
}

func (fb *FileBrowser) loadPrivateKey(keyPath string) (ssh.Signer, error) {
	keyData, err := os.ReadFile(keyPath)
	if err != nil {
		return nil, err
	}

	key, err := ssh.ParsePrivateKey(keyData)
	if err != nil && fb.passEntry.Text != "" {
		key, err = ssh.ParsePrivateKeyWithPassphrase(keyData, []byte(fb.passEntry.Text))
	}
	return key, err
}
