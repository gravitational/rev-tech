package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/storage"
	"fyne.io/fyne/v2/theme"
	"fyne.io/fyne/v2/widget"
	"github.com/kevinburke/ssh_config"
)

func (fb *FileBrowser) initializeSSHControls() {
	fb.hostEntry = widget.NewEntry()
	fb.hostEntry.SetPlaceHolder("hostname/alias (e.g., server1)")
	fb.hostEntry.SetMinRowsVisible(1)
	fb.hostEntry.OnSubmitted = func(_ string) { fb.connectToSSH() }

	fb.userEntry = widget.NewEntry()
	fb.userEntry.SetPlaceHolder("username")
	fb.userEntry.SetMinRowsVisible(1)
	fb.userEntry.OnSubmitted = func(_ string) { fb.connectToSSH() }

	fb.passEntry = widget.NewPasswordEntry()
	fb.passEntry.SetPlaceHolder("password/passphrase")
	fb.passEntry.SetMinRowsVisible(1)
	fb.passEntry.OnSubmitted = func(_ string) { fb.connectToSSH() }

	fb.keyEntry = widget.NewEntry()
	fb.keyEntry.SetPlaceHolder("SSH key path")
	fb.keyEntry.SetMinRowsVisible(1)
	fb.keyEntry.OnSubmitted = func(_ string) { fb.connectToSSH() }

	fb.keyBrowseBtn = widget.NewButtonWithIcon("", theme.FolderOpenIcon(), fb.browseForKeyFile)
	fb.useConfigCheck = widget.NewCheck("Use SSH config", nil)
	fb.useConfigCheck.SetChecked(true)

	fb.connectButton = widget.NewButton("Connect", fb.connectToSSH)
	fb.connectButton.Resize(fyne.NewSize(120, 40))

	fb.terminalBtn = widget.NewButtonWithIcon("Terminal", theme.ComputerIcon(), fb.openSSHTerminal)
	fb.terminalBtn.Disable()

	fb.saveSettingsBtn = widget.NewButtonWithIcon("Save", theme.DocumentSaveIcon(), fb.saveSSHSettings)
	fb.loadSettingsBtn = widget.NewButtonWithIcon("Load", theme.FolderOpenIcon(), fb.loadSSHSettings)
	fb.clearSettingsBtn = widget.NewButtonWithIcon("Clear", theme.ContentClearIcon(), fb.clearSSHSettings)
	fb.deleteSettingsBtn = widget.NewButtonWithIcon("Delete", theme.DeleteIcon(), fb.deleteCurrentSavedSettings)

	fb.savedSettingsSelect = widget.NewSelect([]string{}, fb.onSavedSettingSelected)
	fb.savedSettingsSelect.PlaceHolder = "Saved connections..."
	fb.refreshSavedSettingsDropdown()

	fb.teleportHelpBtn = widget.NewButtonWithIcon("Teleport Setup", theme.HelpIcon(), fb.showTeleportHelp)

	fb.hostEntry.OnChanged = func(text string) {
		if fb.useConfigCheck.Checked && text != "" {
			fb.previewSSHConfig(text)
		}
	}
}

func (fb *FileBrowser) browseForKeyFile() {
	fileDialog := dialog.NewFileOpen(func(reader fyne.URIReadCloser, err error) {
		if err != nil {
			dialog.ShowError(err, fb.mainWindow)
			return
		}
		if reader == nil {
			return
		}
		defer reader.Close()
		fb.keyEntry.SetText(reader.URI().Path())
	}, fb.mainWindow)

	if homeDir, err := os.UserHomeDir(); err == nil {
		sshDir := filepath.Join(homeDir, ".ssh")
		if _, statErr := os.Stat(sshDir); statErr == nil {
			if sshURI := storage.NewFileURI(sshDir); sshURI != nil {
				if listable, listErr := storage.ListerForURI(sshURI); listErr == nil {
					fileDialog.SetLocation(listable)
				}
			}
		}
	}

	fileDialog.SetFilter(storage.NewExtensionFileFilter([]string{".pem", ".key", ".pub", ""}))
	fileDialog.Show()
}

func (fb *FileBrowser) openSSHTerminal() {
	if fb.hostEntry.Text == "" {
		dialog.ShowError(fmt.Errorf("no host specified"), fb.mainWindow)
		return
	}

	host := fb.hostEntry.Text
	var sshArgs []string

	if fb.userEntry.Text != "" {
		sshArgs = append(sshArgs, "-l", fb.userEntry.Text)
	}

	if fb.keyEntry.Text != "" {
		sshArgs = append(sshArgs, "-i", fb.keyEntry.Text)
	} else if fb.useConfigCheck.Checked {
		for _, kp := range ssh_config.GetAll(host, "IdentityFile") {
			if strings.HasPrefix(kp, "~/") {
				homeDir, _ := os.UserHomeDir()
				kp = filepath.Join(homeDir, kp[2:])
			}
			if _, err := os.Stat(kp); err == nil {
				sshArgs = append(sshArgs, "-i", kp)
				break
			}
		}
	}

	sshArgs = append(sshArgs, host)
	fb.remoteStatusLabel.SetText("Opening terminal session...")

	go func() {
		var cmd *exec.Cmd

		switch runtime.GOOS {
		case "darwin":
			script := fmt.Sprintf(`tell application "Terminal"
				activate
				do script "ssh %s"
			end tell`, strings.Join(sshArgs, " "))
			cmd = exec.Command("osascript", "-e", script)

		case "linux":
			terminals := []struct {
				name string
				args []string
			}{
				{"gnome-terminal", []string{"--", "ssh"}},
				{"konsole", []string{"-e", "ssh"}},
				{"xfce4-terminal", []string{"-e", "ssh"}},
				{"xterm", []string{"-e", "ssh"}},
				{"terminator", []string{"-e", "ssh"}},
				{"alacritty", []string{"-e", "ssh"}},
				{"kitty", []string{"ssh"}},
			}

			for _, term := range terminals {
				if _, err := exec.LookPath(term.name); err == nil {
					cmd = exec.Command(term.name, append(term.args, sshArgs...)...)
					break
				}
			}

			if cmd == nil {
				fb.remoteStatusLabel.SetText("❌ No terminal emulator found")
				return
			}

		case "windows":
			cmd = exec.Command("cmd", append([]string{"/c", "start", "ssh"}, sshArgs...)...)

		default:
			fb.remoteStatusLabel.SetText("❌ Unsupported operating system")
			return
		}

		if err := cmd.Start(); err != nil {
			fb.remoteStatusLabel.SetText(fmt.Sprintf("❌ Failed to open terminal: %v", err))
			return
		}

		fb.remoteStatusLabel.SetText("✅ Terminal session opened")
	}()
}

func (fb *FileBrowser) showAvailableHosts() {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		dialog.ShowError(fmt.Errorf("could not find home directory: %v", err), fb.mainWindow)
		return
	}

	content, err := os.ReadFile(filepath.Join(homeDir, ".ssh", "config"))
	if err != nil {
		dialog.ShowError(fmt.Errorf("could not read SSH config: %v", err), fb.mainWindow)
		return
	}

	hosts := extractHostsFromConfig(string(content))

	if len(hosts) == 0 {
		dialog.ShowInformation("SSH Hosts", "No host definitions found in ~/.ssh/config", fb.mainWindow)
		return
	}

	hostList := widget.NewList(
		func() int { return len(hosts) },
		func() fyne.CanvasObject { return widget.NewLabel("Host") },
		func(id widget.ListItemID, item fyne.CanvasObject) {
			if id < len(hosts) {
				item.(*widget.Label).SetText(hosts[id])
			}
		},
	)

	hostList.OnSelected = func(id widget.ListItemID) {
		if id < len(hosts) {
			fb.hostEntry.SetText(hosts[id])
			fb.previewSSHConfig(hosts[id])
		}
	}

	hostDialog := dialog.NewCustom("Available SSH Hosts", "Close",
		container.NewBorder(
			widget.NewLabel("Select a host from your SSH config:"),
			nil, nil, nil,
			hostList,
		), fb.mainWindow)
	hostDialog.Resize(fyne.NewSize(400, 300))
	hostDialog.Show()
}

func (fb *FileBrowser) previewSSHConfig(host string) {
	cleanHost := strings.TrimSuffix(host, " (pattern)")

	hostname := ssh_config.Get(cleanHost, "HostName")
	port := ssh_config.Get(cleanHost, "Port")
	user := ssh_config.Get(cleanHost, "User")
	proxyCommand := ssh_config.Get(cleanHost, "ProxyCommand")
	proxyJump := ssh_config.Get(cleanHost, "ProxyJump")

	if hostname == "" {
		hostname = cleanHost
	}
	if port == "" {
		port = "22"
	}
	if user == "" {
		user = "(current user)"
	}

	preview := fmt.Sprintf("Config: %s@%s:%s", user, hostname, port)

	if proxyCommand != "" {
		preview += " via ProxyCommand"
	} else if proxyJump != "" {
		preview += fmt.Sprintf(" via ProxyJump: %s", proxyJump)
	}

	fb.remoteStatusLabel.SetText(preview)
}

func extractHostsFromConfig(content string) []string {
	var hosts []string

	for _, line := range strings.Split(content, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		if strings.HasPrefix(strings.ToLower(line), "host ") {
			hostLine := strings.TrimPrefix(strings.TrimPrefix(line, "host "), "Host ")

			for _, pattern := range strings.Fields(hostLine) {
				pattern = strings.TrimSpace(pattern)
				if pattern == "" || strings.HasPrefix(pattern, "!") {
					continue
				}

				if strings.Contains(pattern, "*") || strings.Contains(pattern, "?") {
					hosts = append(hosts, pattern+" (pattern)")
				} else {
					hosts = append(hosts, pattern)
				}
			}
		}
	}

	return hosts
}

func (fb *FileBrowser) showTeleportHelp() {
	helpText := `Connecting to Teleport Protected Servers

To connect to servers protected by Teleport through this SSH client:

1. Configure SSH for Teleport
   Run this command to get the SSH configuration:
   
   tsh config
   
   Add the output to your SSH config file (~/.ssh/config).

2. List Available Servers
   Run this command to see your accessible servers:
   
   tsh ls

3. Host Name Format
   When connecting, use the full host name format:
   
   <nodename>.<cluster>
   
   Example:
   If your node name is "myhost" and your cluster is 
   "example.teleport.sh", enter:
   
   myhost.example.teleport.sh

4. Login First
   Make sure you're logged in to Teleport:
   
   tsh login --proxy=<your-proxy>

Tips:
- The "Use SSH config" checkbox should be enabled
- Your Teleport proxy will handle authentication
- Use tsh status to check your login status`

	content := widget.NewRichTextFromMarkdown(`## Connecting to Teleport Protected Servers

To connect to servers protected by Teleport through this SSH client:

### 1. Configure SSH for Teleport

Run: ` + "`tsh config`" + ` and add output to ~/.ssh/config

### 2. List Available Servers

Run: ` + "`tsh ls`" + `

### 3. Host Name Format

Use: ` + "`<nodename>.<cluster>`" + ` (e.g., myhost.example.teleport.sh)

### 4. Login First

Run: ` + "`tsh login --proxy=<your-proxy>`" + `

### Tips
- Enable "Use SSH config"
- Check status with ` + "`tsh status`")

	scroll := container.NewVScroll(content)
	scroll.SetMinSize(fyne.NewSize(500, 400))

	copyBtn := widget.NewButtonWithIcon("Copy Instructions", theme.ContentCopyIcon(), func() {
		fb.mainWindow.Clipboard().SetContent(helpText)
		fb.remoteStatusLabel.SetText("✅ Teleport instructions copied to clipboard")
	})

	dialogContent := container.NewBorder(nil, copyBtn, nil, nil, scroll)
	d := dialog.NewCustom("Teleport Setup Help", "Close", dialogContent, fb.mainWindow)
	d.Resize(fyne.NewSize(550, 500))
	d.Show()
}
