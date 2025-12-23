package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/storage"
	"fyne.io/fyne/v2/theme"
	"fyne.io/fyne/v2/widget"

	"github.com/kevinburke/ssh_config"
	"github.com/pkg/sftp"
	"golang.org/x/crypto/ssh"
	"golang.org/x/crypto/ssh/agent"
)

type RemoteFile struct {
	Name    string
	Size    int64
	ModTime time.Time
	IsDir   bool
}

type SSHConnection struct {
	client     *ssh.Client
	sftpClient *sftp.Client
	host       string
	connected  bool
}

type FileBrowser struct {
	// Local browser
	currentPath     string
	fileList        *widget.List
	folderTree      *widget.Tree
	pathLabel       *widget.Label
	upButton        *widget.Button
	homeButton      *widget.Button
	scpUploadBtn    *widget.Button
	deleteLocalBtn  *widget.Button
	files           []fs.DirEntry
	statusLabel     *widget.Label
	treeData        map[string][]string
	selectedFiles   []string
	localSortColumn string
	localSortAsc    bool
	localNameBtn    *widget.Button
	localSizeBtn    *widget.Button
	localDateBtn    *widget.Button
	showLocalHidden *widget.Check

	// Remote SSH browser
	sshConn             *SSHConnection
	remoteCurrentPath   string
	remoteFileList      *widget.List
	remotePathEntry     *widget.Entry
	remoteUpButton      *widget.Button
	remoteHomeButton    *widget.Button
	remoteFiles         []RemoteFile
	remoteStatusLabel   *widget.Label
	selectedRemoteFiles []string
	scpDownloadBtn      *widget.Button
	deleteRemoteBtn     *widget.Button
	remoteSortColumn    string
	remoteSortAsc       bool
	remoteNameBtn       *widget.Button
	remoteSizeBtn       *widget.Button
	remoteDateBtn       *widget.Button
	showRemoteHidden    *widget.Check

	// SSH connection controls
	hostEntry          *widget.Entry
	userEntry          *widget.Entry
	passEntry          *widget.Entry
	keyEntry           *widget.Entry
	connectButton      *widget.Button
	terminalBtn        *widget.Button
	useConfigCheck     *widget.Check
	keyBrowseBtn       *widget.Button
	saveSettingsBtn    *widget.Button
	loadSettingsBtn    *widget.Button
	clearSettingsBtn   *widget.Button
	deleteSettingsBtn  *widget.Button
	savedSettingsSelect *widget.Select
	teleportHelpBtn     *widget.Button

	mainWindow fyne.Window
}

// SSHSettings represents saved SSH connection settings
type SSHSettings struct {
	Name      string `json:"name"`
	Host      string `json:"host"`
	User      string `json:"user"`
	KeyPath   string `json:"key_path"`
	UseConfig bool   `json:"use_config"`
}

// SSHSettingsStore holds multiple saved settings
type SSHSettingsStore struct {
	Settings []SSHSettings `json:"settings"`
	LastUsed string        `json:"last_used"`
}

func main() {
	myApp := app.New()
	myWindow := myApp.NewWindow("Remote Server File Navigator")
	myWindow.Resize(fyne.NewSize(1200, 900))

	browser := NewFileBrowser(myWindow)

	// Create main layout with local and remote panels
	localPanel := browser.createLocalPanel()
	remotePanel := browser.createRemotePanel()

	// Create horizontal split: local on left, remote on right
	mainSplit := container.NewHSplit(localPanel, remotePanel)
	mainSplit.SetOffset(0.5) // 50% for local, 50% for remote

	// Create the main layout
	content := container.NewBorder(
		widget.NewLabel("🔗 Local & Remote File Browser"), // top
		widget.NewLabel("Ready"),                          // bottom
		nil,                                               // left
		nil,                                               // right
		mainSplit,                                         // center
	)

	myWindow.SetContent(content)

	// Navigate to current directory AFTER window is shown using a goroutine
	go func() {
		time.Sleep(100 * time.Millisecond) // Small delay to ensure UI is ready
		currentDir, _ := os.Getwd()
		browser.NavigateTo(currentDir)
	}()

	myWindow.ShowAndRun()
}

func NewFileBrowser(window fyne.Window) *FileBrowser {
	browser := &FileBrowser{
		treeData:            make(map[string][]string),
		sshConn:             &SSHConnection{},
		mainWindow:          window,
		selectedFiles:       make([]string, 0),
		selectedRemoteFiles: make([]string, 0),
		localSortColumn:     "name",
		localSortAsc:        true,
		remoteSortColumn:    "name",
		remoteSortAsc:       true,
	}

	browser.initializeLocalBrowser()
	browser.initializeRemoteBrowser()
	browser.initializeSSHControls()

	return browser
}

func (fb *FileBrowser) initializeLocalBrowser() {
	fb.pathLabel = widget.NewLabel("")
	fb.statusLabel = widget.NewLabel("Local: Ready")

	// Show hidden files checkbox - initialize early
	fb.showLocalHidden = widget.NewCheck("Show Hidden", func(checked bool) {
		fb.fileList.Refresh()
	})

	// Sort buttons for local files
	fb.localNameBtn = widget.NewButton("Name ▲", func() { fb.sortLocalFiles("name") })
	fb.localSizeBtn = widget.NewButton("Size", func() { fb.sortLocalFiles("size") })
	fb.localDateBtn = widget.NewButton("Date", func() { fb.sortLocalFiles("date") })

	// Create folder tree
	fb.folderTree = widget.NewTree(
		func(uid widget.TreeNodeID) []widget.TreeNodeID {
			return fb.getTreeChildren(uid)
		},
		func(uid widget.TreeNodeID) bool {
			path := string(uid)
			if path == "" {
				return true
			}
			children := fb.getDirectories(path)
			return len(children) > 0
		},
		func(branch bool) fyne.CanvasObject {
			return widget.NewLabel("📁 Folder")
		},
		func(uid widget.TreeNodeID, branch bool, item fyne.CanvasObject) {
			path := string(uid)
			var name string
			if path == "" {
				name = "💻 Computer"
			} else {
				name = filepath.Base(path)
				if name == "." || name == path {
					name = path
				}
			}

			label := item.(*widget.Label)
			label.SetText("📁 " + name)
		},
	)

	fb.folderTree.OnSelected = func(uid widget.TreeNodeID) {
		path := string(uid)
		if path != "" {
			fb.NavigateTo(path)
		}
	}

	// Create file list with selection support
	fb.fileList = widget.NewList(
		func() int {
			return len(fb.getVisibleLocalFiles())
		},
		func() fyne.CanvasObject {
			check := widget.NewCheck("", nil)
			nameLabel := widget.NewLabel("Template File Name")
			sizeLabel := widget.NewLabel("999.9 MB")
			dateLabel := widget.NewLabel("2024-01-01 00:00")
			sizeLabel.Alignment = fyne.TextAlignTrailing
			return container.NewHBox(
				check,
				container.NewGridWrap(fyne.NewSize(250, 20), nameLabel),
				container.NewGridWrap(fyne.NewSize(80, 20), sizeLabel),
				container.NewGridWrap(fyne.NewSize(120, 20), dateLabel),
			)
		},
		func(id widget.ListItemID, item fyne.CanvasObject) {
			files := fb.getVisibleLocalFiles()
			if id >= len(files) {
				return
			}

			entry := files[id]
			box := item.(*fyne.Container)
			check := box.Objects[0].(*widget.Check)
			nameContainer := box.Objects[1].(*fyne.Container)
			sizeContainer := box.Objects[2].(*fyne.Container)
			dateContainer := box.Objects[3].(*fyne.Container)
			nameLabel := nameContainer.Objects[0].(*widget.Label)
			sizeLabel := sizeContainer.Objects[0].(*widget.Label)
			dateLabel := dateContainer.Objects[0].(*widget.Label)

			var icon string
			if entry.IsDir() {
				icon = "📁 "
			} else {
				icon = "📄 "
			}

			info, _ := entry.Info()
			var sizeStr string
			var dateStr string
			if info != nil {
				if entry.IsDir() {
					sizeStr = "<DIR>"
				} else {
					sizeStr = formatFileSize(info.Size())
				}
				dateStr = info.ModTime().Format("2006-01-02 15:04")
			}

			nameLabel.SetText(icon + entry.Name())
			sizeLabel.SetText(sizeStr)
			dateLabel.SetText(dateStr)

			// Handle checkbox for file selection
			filePath := filepath.Join(fb.currentPath, entry.Name())
			check.SetChecked(fb.isFileSelected(filePath))
			check.OnChanged = func(checked bool) {
				if checked {
					fb.addSelectedFile(filePath)
				} else {
					fb.removeSelectedFile(filePath)
				}
				fb.updateSCPButtonState()
			}
		},
	)

	fb.fileList.OnSelected = func(id widget.ListItemID) {
		files := fb.getVisibleLocalFiles()
		if id >= len(files) {
			return
		}

		entry := files[id]
		if entry.IsDir() {
			newPath := filepath.Join(fb.currentPath, entry.Name())
			fb.NavigateTo(newPath)
			fb.folderTree.Select(widget.TreeNodeID(newPath))
		}
	}

	// Navigation buttons
	fb.upButton = widget.NewButtonWithIcon("Up", theme.NavigateBackIcon(),
		func() {
			parentDir := filepath.Dir(fb.currentPath)
			if parentDir != fb.currentPath {
				fb.NavigateTo(parentDir)
				fb.folderTree.Select(widget.TreeNodeID(parentDir))
			}
		})

	fb.homeButton = widget.NewButtonWithIcon("Home", theme.HomeIcon(),
		func() {
			homeDir, err := os.UserHomeDir()
			if err == nil {
				fb.NavigateTo(homeDir)
				fb.folderTree.Select(widget.TreeNodeID(homeDir))
			}
		})

	// SCP Upload button
	fb.scpUploadBtn = widget.NewButtonWithIcon("SCP Upload ⬆", theme.UploadIcon(), fb.scpUploadFiles)
	fb.scpUploadBtn.Disable() // Initially disabled

	// Delete Local button
	fb.deleteLocalBtn = widget.NewButtonWithIcon("Delete", theme.DeleteIcon(), fb.confirmDeleteLocalFiles)
	fb.deleteLocalBtn.Disable() // Initially disabled
}

func (fb *FileBrowser) initializeRemoteBrowser() {
	fb.remoteStatusLabel = widget.NewLabel("Remote: Not connected")
	fb.remoteCurrentPath = "/"

	// Editable path entry
	fb.remotePathEntry = widget.NewEntry()
	fb.remotePathEntry.SetPlaceHolder("/path/to/directory")
	fb.remotePathEntry.SetText("/")
	fb.remotePathEntry.OnSubmitted = func(path string) {
		if fb.sshConn.connected && path != "" {
			fb.RemoteNavigateTo(path)
		}
	}

	// Show hidden files checkbox
	fb.showRemoteHidden = widget.NewCheck("Show Hidden", func(checked bool) {
		fb.remoteFileList.Refresh()
	})

	// Sort buttons for remote files
	fb.remoteNameBtn = widget.NewButton("Name ▲", func() { fb.sortRemoteFiles("name") })
	fb.remoteSizeBtn = widget.NewButton("Size", func() { fb.sortRemoteFiles("size") })
	fb.remoteDateBtn = widget.NewButton("Date", func() { fb.sortRemoteFiles("date") })

	// Create remote file list with selection support
	fb.remoteFileList = widget.NewList(
		func() int {
			return len(fb.getVisibleRemoteFiles())
		},
		func() fyne.CanvasObject {
			check := widget.NewCheck("", nil)
			nameLabel := widget.NewLabel("Template Remote File Name")
			sizeLabel := widget.NewLabel("999.9 MB")
			dateLabel := widget.NewLabel("2024-01-01 00:00")
			sizeLabel.Alignment = fyne.TextAlignTrailing
			return container.NewHBox(
				check,
				container.NewGridWrap(fyne.NewSize(250, 20), nameLabel),
				container.NewGridWrap(fyne.NewSize(80, 20), sizeLabel),
				container.NewGridWrap(fyne.NewSize(120, 20), dateLabel),
			)
		},
		func(id widget.ListItemID, item fyne.CanvasObject) {
			files := fb.getVisibleRemoteFiles()
			if id >= len(files) {
				return
			}

			file := files[id]
			box := item.(*fyne.Container)
			check := box.Objects[0].(*widget.Check)
			nameContainer := box.Objects[1].(*fyne.Container)
			sizeContainer := box.Objects[2].(*fyne.Container)
			dateContainer := box.Objects[3].(*fyne.Container)
			nameLabel := nameContainer.Objects[0].(*widget.Label)
			sizeLabel := sizeContainer.Objects[0].(*widget.Label)
			dateLabel := dateContainer.Objects[0].(*widget.Label)

			var icon string
			var sizeStr string
			if file.IsDir {
				icon = "📁 "
				sizeStr = "<DIR>"
			} else {
				icon = "📄 "
				sizeStr = formatFileSize(file.Size)
			}

			nameLabel.SetText(icon + file.Name)
			sizeLabel.SetText(sizeStr)
			dateLabel.SetText(file.ModTime.Format("2006-01-02 15:04"))

			// Handle checkbox for remote file selection
			var filePath string
			if fb.remoteCurrentPath == "/" {
				filePath = "/" + file.Name
			} else {
				filePath = fb.remoteCurrentPath + "/" + file.Name
			}

			check.SetChecked(fb.isRemoteFileSelected(filePath))
			check.OnChanged = func(checked bool) {
				if checked {
					fb.addSelectedRemoteFile(filePath)
				} else {
					fb.removeSelectedRemoteFile(filePath)
				}
				fb.updateDownloadButtonState()
			}
		},
	)

	fb.remoteFileList.OnSelected = func(id widget.ListItemID) {
		files := fb.getVisibleRemoteFiles()
		if id >= len(files) || !fb.sshConn.connected {
			return
		}

		file := files[id]
		if file.IsDir {
			var newPath string
			if fb.remoteCurrentPath == "/" {
				newPath = "/" + file.Name
			} else {
				newPath = fb.remoteCurrentPath + "/" + file.Name
			}

			fb.RemoteNavigateTo(newPath)
		} else {
			fb.remoteStatusLabel.SetText(fmt.Sprintf("Selected: %s (%s)",
				file.Name, formatFileSize(file.Size)))
		}
	}

	// Remote navigation buttons
	fb.remoteUpButton = widget.NewButtonWithIcon("Up", theme.NavigateBackIcon(),
		func() {
			if !fb.sshConn.connected {
				return
			}
			parentDir := filepath.Dir(fb.remoteCurrentPath)
			if parentDir != fb.remoteCurrentPath && parentDir != "." {
				fb.RemoteNavigateTo(parentDir)
			}
		})

	fb.remoteHomeButton = widget.NewButtonWithIcon("Home", theme.HomeIcon(),
		func() {
			if fb.sshConn.connected {
				homeDir, err := fb.getRemoteHomeDir()
				if err != nil || homeDir == "" {
					homeDir = "/"
				}
				fb.RemoteNavigateTo(homeDir)
			}
		})

	// SCP Download button
	fb.scpDownloadBtn = widget.NewButtonWithIcon("SCP Download ⬇", theme.DownloadIcon(), fb.scpDownloadFiles)
	fb.scpDownloadBtn.Disable() // Initially disabled

	// Delete Remote button
	fb.deleteRemoteBtn = widget.NewButtonWithIcon("Delete", theme.DeleteIcon(), fb.confirmDeleteRemoteFiles)
	fb.deleteRemoteBtn.Disable() // Initially disabled
}

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
	fb.terminalBtn.Disable() // Initially disabled until connected

	// Settings buttons
	fb.saveSettingsBtn = widget.NewButtonWithIcon("Save", theme.DocumentSaveIcon(), fb.saveSSHSettings)
	fb.loadSettingsBtn = widget.NewButtonWithIcon("Load", theme.FolderOpenIcon(), fb.loadSSHSettings)
	fb.clearSettingsBtn = widget.NewButtonWithIcon("Clear", theme.ContentClearIcon(), fb.clearSSHSettings)
	fb.deleteSettingsBtn = widget.NewButtonWithIcon("Delete", theme.DeleteIcon(), fb.deleteCurrentSavedSettings)

	// Saved settings dropdown
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

Run this command to get the SSH configuration:

` + "```" + `
tsh config
` + "```" + `

Add the output to your SSH config file (~/.ssh/config).

### 2. List Available Servers

Run this command to see your accessible servers:

` + "```" + `
tsh ls
` + "```" + `

### 3. Host Name Format

When connecting, use the full host name format:

` + "```" + `
<nodename>.<cluster>
` + "```" + `

**Example:**
If your node name is ` + "`myhost`" + ` and your cluster is ` + "`example.teleport.sh`" + `, enter:

` + "```" + `
myhost.example.teleport.sh
` + "```" + `

### 4. Login First

Make sure you're logged in to Teleport:

` + "```" + `
tsh login --proxy=<your-proxy>
` + "```" + `

### Tips
- The "Use SSH config" checkbox should be enabled
- Your Teleport proxy will handle authentication
- Use ` + "`tsh status`" + ` to check your login status`)

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


func (fb *FileBrowser) getSettingsFilePath() string {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "ssh_browser_settings.json"
	}
	configDir := filepath.Join(homeDir, ".config", "go-file-browser")
	os.MkdirAll(configDir, 0700)
	return filepath.Join(configDir, "ssh_settings.json")
}

func (fb *FileBrowser) loadSettingsStore() (*SSHSettingsStore, error) {
	settingsPath := fb.getSettingsFilePath()

	data, err := os.ReadFile(settingsPath)
	if err != nil {
		if os.IsNotExist(err) {
			return &SSHSettingsStore{Settings: []SSHSettings{}}, nil
		}
		return nil, err
	}

	var store SSHSettingsStore
	err = json.Unmarshal(data, &store)
	if err != nil {
		return nil, err
	}

	return &store, nil
}

func (fb *FileBrowser) saveSettingsStore(store *SSHSettingsStore) error {
	data, err := json.MarshalIndent(store, "", "  ")
	if err != nil {
		return err
	}

	settingsPath := fb.getSettingsFilePath()
	return os.WriteFile(settingsPath, data, 0600)
}

func (fb *FileBrowser) refreshSavedSettingsDropdown() {
	store, err := fb.loadSettingsStore()
	if err != nil {
		return
	}

	var options []string
	for _, s := range store.Settings {
		options = append(options, s.Name)
	}

	fb.savedSettingsSelect.Options = options
	fb.savedSettingsSelect.Refresh()

	// Select last used if available
	if store.LastUsed != "" {
		for _, opt := range options {
			if opt == store.LastUsed {
				fb.savedSettingsSelect.SetSelected(store.LastUsed)
				break
			}
		}
	}
}

func (fb *FileBrowser) onSavedSettingSelected(name string) {
	if name == "" {
		return
	}

	store, err := fb.loadSettingsStore()
	if err != nil {
		return
	}

	for _, s := range store.Settings {
		if s.Name == name {
			fb.hostEntry.SetText(s.Host)
			fb.userEntry.SetText(s.User)
			fb.keyEntry.SetText(s.KeyPath)
			fb.useConfigCheck.SetChecked(s.UseConfig)
			fb.passEntry.SetText("")

			// Update last used
			store.LastUsed = name
			fb.saveSettingsStore(store)

			fb.remoteStatusLabel.SetText(fmt.Sprintf("Loaded: %s (enter password if needed)", name))

			if s.UseConfig && s.Host != "" {
				fb.previewSSHConfig(s.Host)
			}
			break
		}
	}
}

func (fb *FileBrowser) saveSSHSettings() {
	if fb.hostEntry.Text == "" {
		dialog.ShowError(fmt.Errorf("no host specified to save"), fb.mainWindow)
		return
	}

	// Prompt for a name
	nameEntry := widget.NewEntry()
	nameEntry.SetPlaceHolder("Connection name")
	nameEntry.SetText(fb.hostEntry.Text) // Default to host name

	dialog.ShowForm("Save SSH Settings", "Save", "Cancel",
		[]*widget.FormItem{
			widget.NewFormItem("Name", nameEntry),
			widget.NewFormItem("", widget.NewLabel("⚠️ Password will NOT be saved for security")),
		},
		func(confirmed bool) {
			if confirmed && nameEntry.Text != "" {
				fb.doSaveSSHSettings(nameEntry.Text)
			}
		}, fb.mainWindow)
}

func (fb *FileBrowser) doSaveSSHSettings(name string) {
	store, err := fb.loadSettingsStore()
	if err != nil {
		dialog.ShowError(fmt.Errorf("failed to load settings: %v", err), fb.mainWindow)
		return
	}

	newSettings := SSHSettings{
		Name:      name,
		Host:      fb.hostEntry.Text,
		User:      fb.userEntry.Text,
		KeyPath:   fb.keyEntry.Text,
		UseConfig: fb.useConfigCheck.Checked,
	}

	// Check if name already exists and update, or append
	found := false
	for i, s := range store.Settings {
		if s.Name == name {
			store.Settings[i] = newSettings
			found = true
			break
		}
	}

	if !found {
		store.Settings = append(store.Settings, newSettings)
	}

	store.LastUsed = name

	err = fb.saveSettingsStore(store)
	if err != nil {
		dialog.ShowError(fmt.Errorf("failed to save settings: %v", err), fb.mainWindow)
		return
	}

	fb.refreshSavedSettingsDropdown()
	fb.savedSettingsSelect.SetSelected(name)
	fb.remoteStatusLabel.SetText(fmt.Sprintf("✅ Settings saved as '%s'", name))
}

func (fb *FileBrowser) loadSSHSettings() {
	store, err := fb.loadSettingsStore()
	if err != nil {
		dialog.ShowError(fmt.Errorf("failed to load settings: %v", err), fb.mainWindow)
		return
	}

	if len(store.Settings) == 0 {
		dialog.ShowInformation("Load Settings", "No saved settings found.", fb.mainWindow)
		return
	}

	// If there's a last used, load it
	if store.LastUsed != "" {
		fb.onSavedSettingSelected(store.LastUsed)
		return
	}

	// Otherwise load the first one
	fb.onSavedSettingSelected(store.Settings[0].Name)
}

func (fb *FileBrowser) clearSSHSettings() {
	dialog.ShowConfirm("Clear Settings",
		"Do you want to clear the current SSH settings from the form?\n\nThis will not delete saved settings from disk.",
		func(confirmed bool) {
			if confirmed {
				fb.hostEntry.SetText("")
				fb.userEntry.SetText("")
				fb.passEntry.SetText("")
				fb.keyEntry.SetText("")
				fb.useConfigCheck.SetChecked(true)
				fb.savedSettingsSelect.ClearSelected()
				fb.remoteStatusLabel.SetText("Settings cleared")
			}
		}, fb.mainWindow)
}

func (fb *FileBrowser) deleteCurrentSavedSettings() {
	selected := fb.savedSettingsSelect.Selected
	if selected == "" {
		dialog.ShowError(fmt.Errorf("no saved connection selected to delete"), fb.mainWindow)
		return
	}

	dialog.ShowConfirm("Delete Saved Connection",
		fmt.Sprintf("Are you sure you want to delete the saved connection '%s'?\n\nThis cannot be undone.", selected),
		func(confirmed bool) {
			if confirmed {
				fb.doDeleteSavedSettings(selected)
			}
		}, fb.mainWindow)
}

func (fb *FileBrowser) doDeleteSavedSettings(name string) {
	store, err := fb.loadSettingsStore()
	if err != nil {
		dialog.ShowError(fmt.Errorf("failed to load settings: %v", err), fb.mainWindow)
		return
	}

	// Remove the setting
	var newSettings []SSHSettings
	for _, s := range store.Settings {
		if s.Name != name {
			newSettings = append(newSettings, s)
		}
	}
	store.Settings = newSettings

	// Clear last used if it was the deleted one
	if store.LastUsed == name {
		store.LastUsed = ""
		if len(store.Settings) > 0 {
			store.LastUsed = store.Settings[0].Name
		}
	}

	err = fb.saveSettingsStore(store)
	if err != nil {
		dialog.ShowError(fmt.Errorf("failed to save settings: %v", err), fb.mainWindow)
		return
	}

	fb.refreshSavedSettingsDropdown()
	fb.savedSettingsSelect.ClearSelected()
	fb.remoteStatusLabel.SetText(fmt.Sprintf("✅ Deleted saved connection '%s'", name))
}

func (fb *FileBrowser) deleteSSHSettingsFile() {
	settingsPath := fb.getSettingsFilePath()

	if _, err := os.Stat(settingsPath); os.IsNotExist(err) {
		dialog.ShowInformation("Delete Settings", "No saved settings file found.", fb.mainWindow)
		return
	}

	dialog.ShowConfirm("Delete Saved Settings",
		"Are you sure you want to delete the saved settings file?\n\nThis cannot be undone.",
		func(confirmed bool) {
			if confirmed {
				err := os.Remove(settingsPath)
				if err != nil {
					dialog.ShowError(fmt.Errorf("failed to delete settings: %v", err), fb.mainWindow)
					return
				}
				fb.refreshSavedSettingsDropdown()
				fb.remoteStatusLabel.SetText("✅ Saved settings deleted")
			}
		}, fb.mainWindow)
}

func (fb *FileBrowser) getVisibleLocalFiles() []fs.DirEntry {
	if fb.showLocalHidden != nil && fb.showLocalHidden.Checked {
		return fb.files
	}
	var visible []fs.DirEntry
	for _, f := range fb.files {
		if !strings.HasPrefix(f.Name(), ".") {
			visible = append(visible, f)
		}
	}
	return visible
}

func (fb *FileBrowser) getVisibleRemoteFiles() []RemoteFile {
	if fb.showRemoteHidden != nil && fb.showRemoteHidden.Checked {
		return fb.remoteFiles
	}
	var visible []RemoteFile
	for _, f := range fb.remoteFiles {
		if !strings.HasPrefix(f.Name, ".") {
			visible = append(visible, f)
		}
	}
	return visible
}

func (fb *FileBrowser) applyLocalFilter() {
	fb.applySortToLocalFiles()
}

func (fb *FileBrowser) applyRemoteFilter() {
	fb.applySortToRemoteFiles()
}

func (fb *FileBrowser) updateLocalSortButtons() {
	// Reset all buttons
	fb.localNameBtn.SetText("Name")
	fb.localSizeBtn.SetText("Size")
	fb.localDateBtn.SetText("Date")

	// Set the active sort indicator
	arrow := "▲"
	if !fb.localSortAsc {
		arrow = "▼"
	}

	switch fb.localSortColumn {
	case "name":
		fb.localNameBtn.SetText("Name " + arrow)
	case "size":
		fb.localSizeBtn.SetText("Size " + arrow)
	case "date":
		fb.localDateBtn.SetText("Date " + arrow)
	}
}

func (fb *FileBrowser) sortLocalFiles(column string) {
	if fb.localSortColumn == column {
		fb.localSortAsc = !fb.localSortAsc
	} else {
		fb.localSortColumn = column
		fb.localSortAsc = true
	}

	fb.updateLocalSortButtons()
	fb.applyLocalFilter()
	fb.fileList.Refresh()
}

func (fb *FileBrowser) applySortToLocalFiles() {
	sort.Slice(fb.files, func(i, j int) bool {
		iInfo, _ := fb.files[i].Info()
		jInfo, _ := fb.files[j].Info()

		// Directories always come first
		if fb.files[i].IsDir() && !fb.files[j].IsDir() {
			return true
		}
		if !fb.files[i].IsDir() && fb.files[j].IsDir() {
			return false
		}

		var less bool
		switch fb.localSortColumn {
		case "name":
			less = strings.ToLower(fb.files[i].Name()) < strings.ToLower(fb.files[j].Name())
		case "size":
			if iInfo != nil && jInfo != nil {
				less = iInfo.Size() < jInfo.Size()
			} else {
				less = strings.ToLower(fb.files[i].Name()) < strings.ToLower(fb.files[j].Name())
			}
		case "date":
			if iInfo != nil && jInfo != nil {
				less = iInfo.ModTime().Before(jInfo.ModTime())
			} else {
				less = strings.ToLower(fb.files[i].Name()) < strings.ToLower(fb.files[j].Name())
			}
		default:
			less = strings.ToLower(fb.files[i].Name()) < strings.ToLower(fb.files[j].Name())
		}

		if fb.localSortAsc {
			return less
		}
		return !less
	})
}

func (fb *FileBrowser) updateRemoteSortButtons() {
	// Reset all buttons
	fb.remoteNameBtn.SetText("Name")
	fb.remoteSizeBtn.SetText("Size")
	fb.remoteDateBtn.SetText("Date")

	// Set the active sort indicator
	arrow := "▲"
	if !fb.remoteSortAsc {
		arrow = "▼"
	}

	switch fb.remoteSortColumn {
	case "name":
		fb.remoteNameBtn.SetText("Name " + arrow)
	case "size":
		fb.remoteSizeBtn.SetText("Size " + arrow)
	case "date":
		fb.remoteDateBtn.SetText("Date " + arrow)
	}
}

func (fb *FileBrowser) sortRemoteFiles(column string) {
	if fb.remoteSortColumn == column {
		fb.remoteSortAsc = !fb.remoteSortAsc
	} else {
		fb.remoteSortColumn = column
		fb.remoteSortAsc = true
	}

	fb.updateRemoteSortButtons()
	fb.applyRemoteFilter()
	fb.remoteFileList.Refresh()
}

func (fb *FileBrowser) applySortToRemoteFiles() {
	sort.Slice(fb.remoteFiles, func(i, j int) bool {
		// Directories always come first
		if fb.remoteFiles[i].IsDir && !fb.remoteFiles[j].IsDir {
			return true
		}
		if !fb.remoteFiles[i].IsDir && fb.remoteFiles[j].IsDir {
			return false
		}

		var less bool
		switch fb.remoteSortColumn {
		case "name":
			less = strings.ToLower(fb.remoteFiles[i].Name) < strings.ToLower(fb.remoteFiles[j].Name)
		case "size":
			less = fb.remoteFiles[i].Size < fb.remoteFiles[j].Size
		case "date":
			less = fb.remoteFiles[i].ModTime.Before(fb.remoteFiles[j].ModTime)
		default:
			less = strings.ToLower(fb.remoteFiles[i].Name) < strings.ToLower(fb.remoteFiles[j].Name)
		}

		if fb.remoteSortAsc {
			return less
		}
		return !less
	})
}

// Helper methods for local file selection
func (fb *FileBrowser) isFileSelected(filePath string) bool {
	for _, selected := range fb.selectedFiles {
		if selected == filePath {
			return true
		}
	}
	return false
}

func (fb *FileBrowser) addSelectedFile(filePath string) {
	if !fb.isFileSelected(filePath) {
		fb.selectedFiles = append(fb.selectedFiles, filePath)
	}
}

func (fb *FileBrowser) removeSelectedFile(filePath string) {
	for i, selected := range fb.selectedFiles {
		if selected == filePath {
			fb.selectedFiles = append(fb.selectedFiles[:i], fb.selectedFiles[i+1:]...)
			break
		}
	}
}

// Helper methods for remote file selection
func (fb *FileBrowser) isRemoteFileSelected(filePath string) bool {
	for _, selected := range fb.selectedRemoteFiles {
		if selected == filePath {
			return true
		}
	}
	return false
}

func (fb *FileBrowser) addSelectedRemoteFile(filePath string) {
	if !fb.isRemoteFileSelected(filePath) {
		fb.selectedRemoteFiles = append(fb.selectedRemoteFiles, filePath)
	}
}

func (fb *FileBrowser) removeSelectedRemoteFile(filePath string) {
	for i, selected := range fb.selectedRemoteFiles {
		if selected == filePath {
			fb.selectedRemoteFiles = append(fb.selectedRemoteFiles[:i], fb.selectedRemoteFiles[i+1:]...)
			break
		}
	}
}

func (fb *FileBrowser) updateSCPButtonState() {
	if len(fb.selectedFiles) > 0 && fb.sshConn.connected {
		fb.scpUploadBtn.Enable()
		fb.scpUploadBtn.SetText(fmt.Sprintf("SCP Upload ⬆ (%d)", len(fb.selectedFiles)))
	} else {
		fb.scpUploadBtn.Disable()
		fb.scpUploadBtn.SetText("SCP Upload ⬆")
	}

	// Update delete button state
	if len(fb.selectedFiles) > 0 {
		fb.deleteLocalBtn.Enable()
		fb.deleteLocalBtn.SetText(fmt.Sprintf("Delete (%d)", len(fb.selectedFiles)))
	} else {
		fb.deleteLocalBtn.Disable()
		fb.deleteLocalBtn.SetText("Delete")
	}
}

func (fb *FileBrowser) updateDownloadButtonState() {
	if len(fb.selectedRemoteFiles) > 0 && fb.sshConn.connected {
		fb.scpDownloadBtn.Enable()
		fb.scpDownloadBtn.SetText(fmt.Sprintf("SCP Download ⬇ (%d)", len(fb.selectedRemoteFiles)))
		fb.deleteRemoteBtn.Enable()
		fb.deleteRemoteBtn.SetText(fmt.Sprintf("Delete (%d)", len(fb.selectedRemoteFiles)))
	} else {
		fb.scpDownloadBtn.Disable()
		fb.scpDownloadBtn.SetText("SCP Download ⬇")
		fb.deleteRemoteBtn.Disable()
		fb.deleteRemoteBtn.SetText("Delete")
	}
}

func (fb *FileBrowser) confirmDeleteLocalFiles() {
	if len(fb.selectedFiles) == 0 {
		return
	}

	// Build confirmation message
	var msg string
	if len(fb.selectedFiles) == 1 {
		msg = fmt.Sprintf("Are you sure you want to delete:\n%s", filepath.Base(fb.selectedFiles[0]))
	} else {
		msg = fmt.Sprintf("Are you sure you want to delete %d items?\n\n", len(fb.selectedFiles))
		for i, f := range fb.selectedFiles {
			if i < 5 {
				msg += fmt.Sprintf("• %s\n", filepath.Base(f))
			} else {
				msg += fmt.Sprintf("... and %d more", len(fb.selectedFiles)-5)
				break
			}
		}
	}

	dialog.ShowConfirm("Confirm Delete", msg, func(confirmed bool) {
		if confirmed {
			fb.deleteLocalFiles()
		}
	}, fb.mainWindow)
}

func (fb *FileBrowser) deleteLocalFiles() {
	deleted := 0
	failed := 0

	for _, filePath := range fb.selectedFiles {
		info, err := os.Stat(filePath)
		if err != nil {
			failed++
			continue
		}

		if info.IsDir() {
			err = os.RemoveAll(filePath)
		} else {
			err = os.Remove(filePath)
		}

		if err != nil {
			fmt.Printf("Failed to delete %s: %v\n", filePath, err)
			failed++
		} else {
			deleted++
		}
	}

	if failed == 0 {
		fb.statusLabel.SetText(fmt.Sprintf("✅ Deleted %d item(s)", deleted))
	} else {
		fb.statusLabel.SetText(fmt.Sprintf("⚠️ Deleted %d, failed %d", deleted, failed))
	}

	fb.selectedFiles = fb.selectedFiles[:0]
	fb.updateSCPButtonState()
	fb.NavigateTo(fb.currentPath)
}

func (fb *FileBrowser) confirmDeleteRemoteFiles() {
	if len(fb.selectedRemoteFiles) == 0 || !fb.sshConn.connected {
		return
	}

	// Build confirmation message
	var msg string
	if len(fb.selectedRemoteFiles) == 1 {
		msg = fmt.Sprintf("Are you sure you want to delete:\n%s", filepath.Base(fb.selectedRemoteFiles[0]))
	} else {
		msg = fmt.Sprintf("Are you sure you want to delete %d items?\n\n", len(fb.selectedRemoteFiles))
		for i, f := range fb.selectedRemoteFiles {
			if i < 5 {
				msg += fmt.Sprintf("• %s\n", filepath.Base(f))
			} else {
				msg += fmt.Sprintf("... and %d more", len(fb.selectedRemoteFiles)-5)
				break
			}
		}
	}

	dialog.ShowConfirm("Confirm Remote Delete", msg, func(confirmed bool) {
		if confirmed {
			fb.deleteRemoteFiles()
		}
	}, fb.mainWindow)
}

func (fb *FileBrowser) deleteRemoteFiles() {
	if !fb.sshConn.connected {
		return
	}

	fb.remoteStatusLabel.SetText("Deleting files...")

	go func() {
		deleted := 0
		failed := 0

		for _, remotePath := range fb.selectedRemoteFiles {
			info, err := fb.sshConn.sftpClient.Stat(remotePath)
			if err != nil {
				failed++
				continue
			}

			if info.IsDir() {
				err = fb.deleteRemoteDirectory(remotePath)
			} else {
				err = fb.sshConn.sftpClient.Remove(remotePath)
			}

			if err != nil {
				fmt.Printf("Failed to delete %s: %v\n", remotePath, err)
				failed++
			} else {
				deleted++
			}
		}

		if failed == 0 {
			fb.remoteStatusLabel.SetText(fmt.Sprintf("✅ Deleted %d item(s)", deleted))
		} else {
			fb.remoteStatusLabel.SetText(fmt.Sprintf("⚠️ Deleted %d, failed %d", deleted, failed))
		}

		fb.selectedRemoteFiles = fb.selectedRemoteFiles[:0]
		fb.updateDownloadButtonState()
		fb.RemoteNavigateTo(fb.remoteCurrentPath)
	}()
}

func (fb *FileBrowser) deleteRemoteDirectory(path string) error {
	// List all files in directory
	files, err := fb.sshConn.sftpClient.ReadDir(path)
	if err != nil {
		return err
	}

	// Delete contents first
	for _, file := range files {
		fullPath := path + "/" + file.Name()
		if file.IsDir() {
			err = fb.deleteRemoteDirectory(fullPath)
		} else {
			err = fb.sshConn.sftpClient.Remove(fullPath)
		}
		if err != nil {
			return err
		}
	}

	// Delete the directory itself
	return fb.sshConn.sftpClient.RemoveDirectory(path)
}

func (fb *FileBrowser) scpUploadFiles() {
	if len(fb.selectedFiles) == 0 {
		fb.statusLabel.SetText("No files selected for upload")
		return
	}

	if !fb.sshConn.connected {
		fb.statusLabel.SetText("Not connected to remote server")
		return
	}

	// Check if any directories are selected
	var dirs []string
	for _, filePath := range fb.selectedFiles {
		info, err := os.Stat(filePath)
		if err == nil && info.IsDir() {
			dirs = append(dirs, filepath.Base(filePath))
		}
	}

	if len(dirs) > 0 {
		// Prompt user about directory upload
		var msg string
		if len(dirs) == 1 {
			msg = fmt.Sprintf("You have selected a directory:\n• %s\n\nThis will recursively upload all contents. Continue?", dirs[0])
		} else {
			msg = fmt.Sprintf("You have selected %d directories:\n", len(dirs))
			for i, d := range dirs {
				if i < 5 {
					msg += fmt.Sprintf("• %s\n", d)
				} else {
					msg += fmt.Sprintf("... and %d more\n", len(dirs)-5)
					break
				}
			}
			msg += "\nThis will recursively upload all contents. Continue?"
		}

		dialog.ShowConfirm("Recursive Upload", msg, func(confirmed bool) {
			if confirmed {
				fb.doSCPUpload()
			}
		}, fb.mainWindow)
	} else {
		fb.doSCPUpload()
	}
}

func (fb *FileBrowser) doSCPUpload() {
	fb.statusLabel.SetText(fmt.Sprintf("Starting SCP upload of %d item(s)...", len(fb.selectedFiles)))

	go func() {
		uploaded := 0
		failed := 0

		for i, filePath := range fb.selectedFiles {
			filename := filepath.Base(filePath)
			fb.statusLabel.SetText(fmt.Sprintf("SCP uploading %d/%d: %s", i+1, len(fb.selectedFiles), filename))

			err := fb.scpUploadFile(filePath)
			if err != nil {
				fmt.Printf("SCP upload failed for %s: %v\n", filePath, err)
				failed++
			} else {
				uploaded++
			}
		}

		if failed == 0 {
			fb.statusLabel.SetText(fmt.Sprintf("✅ SCP uploaded %d item(s) successfully", uploaded))
		} else {
			fb.statusLabel.SetText(fmt.Sprintf("⚠️ SCP uploaded %d item(s), %d failed", uploaded, failed))
		}

		fb.selectedFiles = fb.selectedFiles[:0]
		fb.updateSCPButtonState()
		fb.fileList.Refresh()

		if fb.sshConn.connected {
			fb.RemoteNavigateTo(fb.remoteCurrentPath)
		}
	}()
}

func (fb *FileBrowser) scpDownloadFiles() {
	if len(fb.selectedRemoteFiles) == 0 {
		fb.remoteStatusLabel.SetText("No files selected for download")
		return
	}

	if !fb.sshConn.connected {
		fb.remoteStatusLabel.SetText("Not connected to remote server")
		return
	}

	// Check if any directories are selected
	var dirs []string
	for _, remotePath := range fb.selectedRemoteFiles {
		info, err := fb.sshConn.sftpClient.Stat(remotePath)
		if err == nil && info.IsDir() {
			dirs = append(dirs, filepath.Base(remotePath))
		}
	}

	if len(dirs) > 0 {
		// Prompt user about directory download
		var msg string
		if len(dirs) == 1 {
			msg = fmt.Sprintf("You have selected a directory:\n• %s\n\nThis will recursively download all contents. Continue?", dirs[0])
		} else {
			msg = fmt.Sprintf("You have selected %d directories:\n", len(dirs))
			for i, d := range dirs {
				if i < 5 {
					msg += fmt.Sprintf("• %s\n", d)
				} else {
					msg += fmt.Sprintf("... and %d more\n", len(dirs)-5)
					break
				}
			}
			msg += "\nThis will recursively download all contents. Continue?"
		}

		dialog.ShowConfirm("Recursive Download", msg, func(confirmed bool) {
			if confirmed {
				fb.doSCPDownload()
			}
		}, fb.mainWindow)
	} else {
		fb.doSCPDownload()
	}
}

func (fb *FileBrowser) doSCPDownload() {
	fb.remoteStatusLabel.SetText(fmt.Sprintf("Starting SCP download of %d item(s)...", len(fb.selectedRemoteFiles)))

	go func() {
		downloaded := 0
		failed := 0

		for i, remotePath := range fb.selectedRemoteFiles {
			filename := filepath.Base(remotePath)
			fb.remoteStatusLabel.SetText(fmt.Sprintf("SCP downloading %d/%d: %s", i+1, len(fb.selectedRemoteFiles), filename))

			err := fb.scpDownloadFile(remotePath)
			if err != nil {
				fmt.Printf("SCP download failed for %s: %v\n", remotePath, err)
				failed++
			} else {
				downloaded++
			}
		}

		if failed == 0 {
			fb.remoteStatusLabel.SetText(fmt.Sprintf("✅ SCP downloaded %d item(s) to %s", downloaded, fb.currentPath))
		} else {
			fb.remoteStatusLabel.SetText(fmt.Sprintf("⚠️ Downloaded %d, ❌ %d failed", downloaded, failed))
		}

		fb.selectedRemoteFiles = fb.selectedRemoteFiles[:0]
		fb.updateDownloadButtonState()
		fb.remoteFileList.Refresh()

		// Refresh local directory to show downloaded files
		fb.NavigateTo(fb.currentPath)
	}()
}

func (fb *FileBrowser) scpDownloadFile(remotePath string) error {
	// Get SSH connection details
	host := fb.hostEntry.Text
	user := fb.userEntry.Text

	if user == "" {
		user = ssh_config.Get(host, "User")
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

	hostname := ssh_config.Get(host, "HostName")
	if hostname == "" {
		hostname = host
	}

	port := ssh_config.Get(host, "Port")
	if port == "" {
		port = "22"
	}

	// Build local destination path
	filename := filepath.Base(remotePath)
	localPath := filepath.Join(fb.currentPath, filename)

	// Check if it's a directory
	info, err := fb.sshConn.sftpClient.Stat(remotePath)
	if err != nil {
		return fmt.Errorf("failed to stat remote path: %v", err)
	}
	isDir := info.IsDir()

	// Build SCP command arguments
	var scpArgs []string

	// Add recursive flag for directories
	if isDir {
		scpArgs = append(scpArgs, "-r")
	}

	if port != "22" {
		scpArgs = append(scpArgs, "-P", port)
	}

	if fb.keyEntry.Text != "" {
		scpArgs = append(scpArgs, "-i", fb.keyEntry.Text)
	} else {
		identityFiles := ssh_config.GetAll(host, "IdentityFile")
		for _, keyPath := range identityFiles {
			if strings.HasPrefix(keyPath, "~/") {
				homeDir, _ := os.UserHomeDir()
				keyPath = filepath.Join(homeDir, keyPath[2:])
			}
			if _, err := os.Stat(keyPath); err == nil {
				scpArgs = append(scpArgs, "-i", keyPath)
				break
			}
		}
	}

	proxyCommand := ssh_config.Get(host, "ProxyCommand")
	if proxyCommand != "" && proxyCommand != "none" {
		scpArgs = append(scpArgs, "-o", fmt.Sprintf("ProxyCommand=%s", proxyCommand))
	}

	scpArgs = append(scpArgs,
		"-o", "StrictHostKeyChecking=no",
		"-o", "UserKnownHostsFile=/dev/null",
	)

	// For download: source is remote, destination is local
	scpArgs = append(scpArgs, fmt.Sprintf("%s@%s:%s", user, hostname, remotePath), localPath)

	cmd := exec.Command("scp", scpArgs...)

	if fb.passEntry.Text != "" {
		cmd.Env = append(os.Environ(), "SSH_ASKPASS_REQUIRE=never")
	}

	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("scp failed: %v, output: %s", err, string(output))
	}

	return nil
}

func (fb *FileBrowser) scpUploadFile(localPath string) error {
	stat, err := os.Stat(localPath)
	if err != nil {
		return fmt.Errorf("failed to stat file: %v", err)
	}

	isDir := stat.IsDir()

	filename := filepath.Base(localPath)
	var remoteFilePath string
	if fb.remoteCurrentPath == "/" {
		remoteFilePath = "/" + filename
	} else {
		remoteFilePath = fb.remoteCurrentPath + "/" + filename
	}

	host := fb.hostEntry.Text
	user := fb.userEntry.Text

	if user == "" {
		user = ssh_config.Get(host, "User")
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

	hostname := ssh_config.Get(host, "HostName")
	if hostname == "" {
		hostname = host
	}

	port := ssh_config.Get(host, "Port")
	if port == "" {
		port = "22"
	}

	var scpArgs []string

	// Add recursive flag for directories
	if isDir {
		scpArgs = append(scpArgs, "-r")
	}

	if port != "22" {
		scpArgs = append(scpArgs, "-P", port)
	}

	if fb.keyEntry.Text != "" {
		scpArgs = append(scpArgs, "-i", fb.keyEntry.Text)
	} else {
		identityFiles := ssh_config.GetAll(host, "IdentityFile")
		for _, keyPath := range identityFiles {
			if strings.HasPrefix(keyPath, "~/") {
				homeDir, _ := os.UserHomeDir()
				keyPath = filepath.Join(homeDir, keyPath[2:])
			}
			if _, err := os.Stat(keyPath); err == nil {
				scpArgs = append(scpArgs, "-i", keyPath)
				break
			}
		}
	}

	proxyCommand := ssh_config.Get(host, "ProxyCommand")
	if proxyCommand != "" && proxyCommand != "none" {
		scpArgs = append(scpArgs, "-o", fmt.Sprintf("ProxyCommand=%s", proxyCommand))
	}

	scpArgs = append(scpArgs,
		"-o", "StrictHostKeyChecking=no",
		"-o", "UserKnownHostsFile=/dev/null",
	)

	scpArgs = append(scpArgs, localPath, fmt.Sprintf("%s@%s:%s", user, hostname, remoteFilePath))

	cmd := exec.Command("scp", scpArgs...)

	if fb.passEntry.Text != "" {
		cmd.Env = append(os.Environ(), "SSH_ASKPASS_REQUIRE=never")
	}

	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("scp failed: %v, output: %s", err, string(output))
	}

	return nil
}

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

			hostAddr := hostname + ":" + port
			client, err = ssh.Dial("tcp", hostAddr, sshConfig)
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

		// Get remote user's home directory
		homeDir, err := fb.getRemoteHomeDir()
		if err != nil || homeDir == "" {
			homeDir = "/"
		}

		fb.RemoteNavigateTo(homeDir)
	}()
}

func (fb *FileBrowser) browseForKeyFile() {
	fileDialog := dialog.NewFileOpen(func(reader fyne.URIReadCloser, err error) {
		if err != nil {
			dialog.ShowError(err, fb.mainWindow)
			return
		}
		if reader == nil {
			return // User cancelled
		}
		defer reader.Close()

		// Get the file path
		filePath := reader.URI().Path()
		fb.keyEntry.SetText(filePath)
	}, fb.mainWindow)

	// Set starting directory to ~/.ssh if it exists
	homeDir, err := os.UserHomeDir()
	if err == nil {
		sshDir := filepath.Join(homeDir, ".ssh")
		if _, statErr := os.Stat(sshDir); statErr == nil {
			sshURI := storage.NewFileURI(sshDir)
			listable, listErr := storage.ListerForURI(sshURI)
			if listErr == nil {
				fileDialog.SetLocation(listable)
			}
		}
	}

	// Filter for common key file extensions
	fileDialog.SetFilter(storage.NewExtensionFileFilter([]string{".pem", ".key", ".pub", ""}))

	fileDialog.Show()
}

func (fb *FileBrowser) openSSHTerminal() {
	if fb.hostEntry.Text == "" {
		dialog.ShowError(fmt.Errorf("no host specified"), fb.mainWindow)
		return
	}

	host := fb.hostEntry.Text
	user := fb.userEntry.Text
	keyPath := fb.keyEntry.Text

	// Build SSH command arguments
	var sshArgs []string

	// Add user if specified
	if user != "" {
		sshArgs = append(sshArgs, "-l", user)
	}

	// Add key if specified
	if keyPath != "" {
		sshArgs = append(sshArgs, "-i", keyPath)
	} else if fb.useConfigCheck.Checked {
		// Try to use keys from SSH config
		identityFiles := ssh_config.GetAll(host, "IdentityFile")
		for _, kp := range identityFiles {
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

	// Add host
	sshArgs = append(sshArgs, host)

	fb.remoteStatusLabel.SetText("Opening terminal session...")

	go func() {
		var cmd *exec.Cmd

		// Detect the operating system and use appropriate terminal
		switch runtime.GOOS {
		case "darwin":
			// macOS - use osascript to open Terminal.app
			script := fmt.Sprintf(`tell application "Terminal"
				activate
				do script "ssh %s"
			end tell`, strings.Join(sshArgs, " "))
			cmd = exec.Command("osascript", "-e", script)

		case "linux":
			// Linux - try common terminal emulators
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
					args := append(term.args, sshArgs...)
					cmd = exec.Command(term.name, args...)
					break
				}
			}

			if cmd == nil {
				fb.remoteStatusLabel.SetText("❌ No terminal emulator found")
				return
			}

		case "windows":
			// Windows - use cmd to start ssh
			allArgs := append([]string{"/c", "start", "ssh"}, sshArgs...)
			cmd = exec.Command("cmd", allArgs...)

		default:
			fb.remoteStatusLabel.SetText("❌ Unsupported operating system")
			return
		}

		err := cmd.Start()
		if err != nil {
			fb.remoteStatusLabel.SetText(fmt.Sprintf("❌ Failed to open terminal: %v", err))
			return
		}

		fb.remoteStatusLabel.SetText("✅ Terminal session opened")
	}()
}

func (fb *FileBrowser) getRemoteHomeDir() (string, error) {
	if fb.sshConn.client == nil {
		return "", fmt.Errorf("not connected")
	}

	session, err := fb.sshConn.client.NewSession()
	if err != nil {
		return "", err
	}
	defer session.Close()

	output, err := session.Output("echo $HOME")
	if err != nil {
		return "", err
	}

	homeDir := strings.TrimSpace(string(output))
	if homeDir == "" {
		return "/", nil
	}

	return homeDir, nil
}

func (fb *FileBrowser) getKnownHostsCallback(configHost string, targetHost string, targetPort string) (ssh.HostKeyCallback, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return nil, fmt.Errorf("failed to get home directory: %v", err)
	}

	// Get known hosts files from SSH config or use defaults
	knownHostsFiles := []string{}

	// Check for UserKnownHostsFile in SSH config
	userKnownHosts := ssh_config.Get(configHost, "UserKnownHostsFile")
	fmt.Printf("DEBUG: configHost='%s', UserKnownHostsFile from config='%s'\n", configHost, userKnownHosts)

	if userKnownHosts != "" {
		// Handle multiple files separated by spaces (but respect quotes)
		files := parseQuotedPaths(userKnownHosts)
		for _, f := range files {
			// Strip surrounding quotes if present
			f = strings.Trim(f, "\"'")

			// Expand ~
			if strings.HasPrefix(f, "~/") {
				f = filepath.Join(homeDir, f[2:])
			} else if strings.HasPrefix(f, "~") {
				f = filepath.Join(homeDir, f[1:])
			}
			knownHostsFiles = append(knownHostsFiles, f)
		}
	}

	// Add default known_hosts file
	defaultKnownHosts := filepath.Join(homeDir, ".ssh", "known_hosts")
	knownHostsFiles = append(knownHostsFiles, defaultKnownHosts)

	// Also check global known_hosts
	globalKnownHosts := "/etc/ssh/ssh_known_hosts"
	if _, statErr := os.Stat(globalKnownHosts); statErr == nil {
		knownHostsFiles = append(knownHostsFiles, globalKnownHosts)
	}

	fmt.Printf("DEBUG: Will check known_hosts files: %v\n", knownHostsFiles)

	// Ensure default known_hosts exists
	if _, statErr := os.Stat(defaultKnownHosts); os.IsNotExist(statErr) {
		sshDir := filepath.Join(homeDir, ".ssh")
		if mkErr := os.MkdirAll(sshDir, 0700); mkErr != nil {
			return nil, fmt.Errorf("failed to create .ssh directory: %v", mkErr)
		}
		if writeErr := os.WriteFile(defaultKnownHosts, []byte{}, 0600); writeErr != nil {
			return nil, fmt.Errorf("failed to create known_hosts file: %v", writeErr)
		}
	}

	// Read and parse all known_hosts files
	type knownKey struct {
		pattern  string
		key      ssh.PublicKey
		filePath string
	}
	knownKeys := []knownKey{}

	for _, knownHostsPath := range knownHostsFiles {
		fmt.Printf("DEBUG: Trying to read known_hosts file: %s\n", knownHostsPath)
		data, readErr := os.ReadFile(knownHostsPath)
		if readErr != nil {
			fmt.Printf("DEBUG: Failed to read %s: %v\n", knownHostsPath, readErr)
			continue
		}

		fmt.Printf("DEBUG: Successfully read %s (%d bytes)\n", knownHostsPath, len(data))

		lines := strings.Split(string(data), "\n")
		for lineNum, line := range lines {
			line = strings.TrimSpace(line)
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}

			fmt.Printf("DEBUG: Processing line %d: %.80s...\n", lineNum+1, line)

			// Handle @cert-authority and @revoked markers
			if strings.HasPrefix(line, "@cert-authority ") {
				line = strings.TrimPrefix(line, "@cert-authority ")
				fmt.Printf("DEBUG: Found @cert-authority line\n")
			} else if strings.HasPrefix(line, "@revoked ") {
				fmt.Printf("DEBUG: Skipping @revoked line\n")
				continue
			}

			// Parse known_hosts line: hostname[,hostname2,...] keytype base64key [comment]
			fields := strings.Fields(line)
			if len(fields) < 3 {
				fmt.Printf("DEBUG: Line has fewer than 3 fields (%d), skipping\n", len(fields))
				continue
			}

			hosts := strings.Split(fields[0], ",")
			keyBytes := []byte(fields[1] + " " + fields[2])
			pubKey, _, _, _, parseErr := ssh.ParseAuthorizedKey(keyBytes)
			if parseErr != nil {
				fmt.Printf("DEBUG: Failed to parse key for hosts %v: %v\n", hosts, parseErr)
				continue
			}

			for _, h := range hosts {
				// Handle hashed hostnames (start with |1|)
				if strings.HasPrefix(h, "|1|") {
					fmt.Printf("DEBUG: Skipping hashed hostname\n")
					continue
				}

				// Normalize the host - remove brackets but preserve port
				origHost := h
				h = strings.TrimPrefix(h, "[")
				if idx := strings.Index(h, "]:"); idx != -1 {
					// [host]:port format
					h = h[:idx] + ":" + h[idx+2:]
				} else {
					h = strings.TrimSuffix(h, "]")
				}

				fmt.Printf("DEBUG: Loaded known host pattern: '%s' from %s\n", h, knownHostsPath)

				knownKeys = append(knownKeys, knownKey{pattern: h, key: pubKey, filePath: knownHostsPath})
				// Also keep original format for matching
				if origHost != h {
					knownKeys = append(knownKeys, knownKey{pattern: origHost, key: pubKey, filePath: knownHostsPath})
				}
			}
		}
	}

	// Function to check if a hostname matches a pattern (supports * and ? wildcards)
	matchHost := func(pattern, hostname string) bool {
		// Handle negation patterns
		if strings.HasPrefix(pattern, "!") {
			return false
		}

		// Exact match first
		if pattern == hostname {
			return true
		}

		// No wildcards, no match
		if !strings.Contains(pattern, "*") && !strings.Contains(pattern, "?") {
			return false
		}

		// Convert glob pattern to regex-like matching
		patternIdx := 0
		hostnameIdx := 0
		starIdx := -1
		matchIdx := 0

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

	return func(hostname string, remote net.Addr, key ssh.PublicKey) error {
		keyFingerprint := ssh.FingerprintSHA256(key)

		// Build list of hostnames to check - use the actual resolved hostname
		hostsToCheck := []string{targetHost}

		// Add with port variations
		if targetPort != "" && targetPort != "22" {
			hostsToCheck = append(hostsToCheck, fmt.Sprintf("%s:%s", targetHost, targetPort))
			hostsToCheck = append(hostsToCheck, fmt.Sprintf("[%s]:%s", targetHost, targetPort))
		}

		// Also check the config alias if different
		if configHost != targetHost {
			hostsToCheck = append(hostsToCheck, configHost)
		}

		// Also check the hostname passed by SSH library
		if hostname != targetHost && hostname != configHost {
			hostsToCheck = append(hostsToCheck, hostname)
			// Try to extract just the host part if it has a port
			if h, _, splitErr := net.SplitHostPort(hostname); splitErr == nil {
				hostsToCheck = append(hostsToCheck, h)
			}
		}

		// Debug: print what we're checking
		fmt.Printf("DEBUG: Checking host keys for hosts: %v\n", hostsToCheck)

		// Check if we have this host in our known keys
		for _, kk := range knownKeys {
			for _, hostCheck := range hostsToCheck {
				matched := matchHost(kk.pattern, hostCheck)
				if matched {
					fmt.Printf("DEBUG: Pattern '%s' matched host '%s'\n", kk.pattern, hostCheck)

					// Found a matching pattern, compare keys
					if ssh.FingerprintSHA256(kk.key) == keyFingerprint {
						fmt.Printf("DEBUG: Key matched!\n")
						return nil
					}
					fmt.Printf("DEBUG: Key fingerprints don't match, checking next key...\n")
				}
			}
		}

		// Check if any pattern matched but keys didn't match
		for _, kk := range knownKeys {
			for _, hostCheck := range hostsToCheck {
				if matchHost(kk.pattern, hostCheck) {
					fmt.Printf("DEBUG: Found matching pattern '%s', accepting (may be cert-authority)\n", kk.pattern)
					return nil
				}
			}
		}

		fmt.Printf("DEBUG: No matching host key found\n")

		// Unknown host - prompt user to accept
		keyType := key.Type()

		accepted := fb.promptHostKeyAcceptance(targetHost, keyType, keyFingerprint, defaultKnownHosts)
		if accepted {
			// Add the key to known_hosts
			addErr := fb.addHostKey(defaultKnownHosts, targetHost, key)
			if addErr != nil {
				return fmt.Errorf("failed to add host key: %v", addErr)
			}
			return nil
		}
		return fmt.Errorf("host key verification rejected by user")
	}, nil
}

func (fb *FileBrowser) promptHostKeyAcceptance(hostname, keyType, fingerprint, knownHostsPath string) bool {
	resultChan := make(chan bool)

	message := fmt.Sprintf("The authenticity of host '%s' can't be established.\n\n"+
		"Host key type: %s\n"+
		"Host key fingerprint:\n%s\n\n"+
		"Are you sure you want to continue connecting?\n"+
		"The key will be added to:\n%s",
		hostname, keyType, fingerprint, knownHostsPath)

	// Run dialog on main thread
	dialog.ShowConfirm("Unknown Host Key", message, func(accepted bool) {
		resultChan <- accepted
	}, fb.mainWindow)

	return <-resultChan
}

func (fb *FileBrowser) addHostKey(knownHostsPath string, hostname string, key ssh.PublicKey) error {
	// Create the known_hosts line manually
	keyBytes := key.Marshal()
	keyBase64 := base64.StdEncoding.EncodeToString(keyBytes)
	line := fmt.Sprintf("%s %s %s", hostname, key.Type(), keyBase64)

	// Append to known_hosts file
	f, err := os.OpenFile(knownHostsPath, os.O_APPEND|os.O_WRONLY|os.O_CREATE, 0600)
	if err != nil {
		return err
	}
	defer f.Close()

	_, err = f.WriteString(line + "\n")
	return err
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

	var authMethods []ssh.AuthMethod

	if sshAuthSock := os.Getenv("SSH_AUTH_SOCK"); sshAuthSock != "" {
		if agentConn, err := net.Dial("unix", sshAuthSock); err == nil {
			agentClient := agent.NewClient(agentConn)
			authMethods = append(authMethods, ssh.PublicKeysCallback(agentClient.Signers))
		}
	}

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

	if fb.keyEntry.Text != "" {
		if key, err := fb.loadPrivateKey(fb.keyEntry.Text); err == nil {
			authMethods = append(authMethods, ssh.PublicKeys(key))
		}
	}

	if fb.passEntry.Text != "" {
		authMethods = append(authMethods, ssh.Password(fb.passEntry.Text))
	}

	authMethods = append(authMethods, ssh.KeyboardInteractive(func(user, instruction string, questions []string, echos []bool) ([]string, error) {
		if len(questions) == 1 && strings.Contains(strings.ToLower(questions[0]), "password") && fb.passEntry.Text != "" {
			return []string{fb.passEntry.Text}, nil
		}
		return nil, fmt.Errorf("interactive authentication not supported")
	}))

	if len(authMethods) == 0 {
		return nil, nil, fmt.Errorf("no authentication methods available")
	}

	hostKeyCallback, hkErr := fb.getKnownHostsCallback(host, hostname, port)
	if hkErr != nil {
		return nil, nil, fmt.Errorf("failed to setup host key verification: %v", hkErr)
	}

	config := &ssh.ClientConfig{
		User:            user,
		Auth:            authMethods,
		HostKeyCallback: hostKeyCallback,
		Timeout:         30 * time.Second,
	}

	var conn net.Conn
	var connErr error

	if proxyJump != "" {
		conn, connErr = fb.connectViaProxyJump(proxyJump, hostname, port, config)
		if connErr != nil {
			return nil, nil, fmt.Errorf("ProxyJump failed: %v", connErr)
		}
		return config, conn, nil
	} else if proxyCommand != "" && proxyCommand != "none" {
		conn, connErr = fb.connectViaProxyCommand(proxyCommand, hostname, port)
		if connErr != nil {
			return nil, nil, fmt.Errorf("ProxyCommand failed: %v", connErr)
		}
		return config, conn, nil
	}

	return config, nil, nil
}

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

	proxyClient, proxyErr := ssh.Dial("tcp", proxyHostname+":"+proxyPort, proxyConfig)
	if proxyErr != nil {
		return nil, fmt.Errorf("failed to connect to proxy %s: %v", proxyHost, proxyErr)
	}

	targetAddr := targetHost + ":" + targetPort
	conn, dialErr := proxyClient.Dial("tcp", targetAddr)
	if dialErr != nil {
		proxyClient.Close()
		return nil, fmt.Errorf("failed to connect through proxy to %s: %v", targetAddr, dialErr)
	}

	return conn, nil
}

func (fb *FileBrowser) connectViaProxyCommand(proxyCommand, targetHost, targetPort string) (net.Conn, error) {
	command := strings.ReplaceAll(proxyCommand, "%h", targetHost)
	command = strings.ReplaceAll(command, "%p", targetPort)

	user := fb.userEntry.Text
	if user == "" {
		if homeDir, hdErr := os.UserHomeDir(); hdErr == nil {
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

	stdin, stdinErr := cmd.StdinPipe()
	if stdinErr != nil {
		return nil, fmt.Errorf("failed to create stdin pipe: %v", stdinErr)
	}

	stdout, stdoutErr := cmd.StdoutPipe()
	if stdoutErr != nil {
		stdin.Close()
		return nil, fmt.Errorf("failed to create stdout pipe: %v", stdoutErr)
	}

	stderr, stderrErr := cmd.StderrPipe()
	if stderrErr != nil {
		stdin.Close()
		stdout.Close()
		return nil, fmt.Errorf("failed to create stderr pipe: %v", stderrErr)
	}

	if startErr := cmd.Start(); startErr != nil {
		stdin.Close()
		stdout.Close()
		stderr.Close()
		return nil, fmt.Errorf("failed to start proxy command '%s': %v", parts[0], startErr)
	}

	go func() {
		buf := make([]byte, 1024)
		for {
			_, readErr := stderr.Read(buf)
			if readErr != nil {
				break
			}
		}
		stderr.Close()
	}()

	conn := &proxyConn{
		stdin:  stdin,
		stdout: stdout,
		stderr: stderr,
		cmd:    cmd,
	}

	return conn, nil
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
			} else {
				if current.Len() > 0 {
					parts = append(parts, current.String())
					current.Reset()
				}
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

type proxyConn struct {
	stdin  io.WriteCloser
	stdout io.ReadCloser
	stderr io.ReadCloser
	cmd    *exec.Cmd
}

func (c *proxyConn) Read(b []byte) (n int, err error) {
	return c.stdout.Read(b)
}

func (c *proxyConn) Write(b []byte) (n int, err error) {
	return c.stdin.Write(b)
}

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

func (c *proxyConn) LocalAddr() net.Addr {
	return &net.UnixAddr{Name: "proxy", Net: "proxy"}
}

func (c *proxyConn) RemoteAddr() net.Addr {
	return &net.UnixAddr{Name: "proxy", Net: "proxy"}
}

func (c *proxyConn) SetDeadline(t time.Time) error {
	return nil
}

func (c *proxyConn) SetReadDeadline(t time.Time) error {
	return nil
}

func (c *proxyConn) SetWriteDeadline(t time.Time) error {
	return nil
}

func (fb *FileBrowser) buildManualSSHConfig(host string) (*ssh.ClientConfig, net.Conn, error) {
	user := fb.userEntry.Text
	pass := fb.passEntry.Text

	if user == "" {
		return nil, nil, fmt.Errorf("username is required for manual connection")
	}

	// Parse host and port
	hostname := host
	port := "22"
	if h, p, splitErr := net.SplitHostPort(host); splitErr == nil {
		hostname = h
		port = p
	}

	var authMethods []ssh.AuthMethod

	if sshAuthSock := os.Getenv("SSH_AUTH_SOCK"); sshAuthSock != "" {
		if agentConn, agentErr := net.Dial("unix", sshAuthSock); agentErr == nil {
			agentClient := agent.NewClient(agentConn)
			authMethods = append(authMethods, ssh.PublicKeysCallback(agentClient.Signers))
		}
	}

	if fb.keyEntry.Text != "" {
		if key, keyErr := fb.loadPrivateKey(fb.keyEntry.Text); keyErr == nil {
			authMethods = append(authMethods, ssh.PublicKeys(key))
		}
	}

	if pass != "" {
		authMethods = append(authMethods, ssh.Password(pass))
	}

	if len(authMethods) == 0 {
		return nil, nil, fmt.Errorf("no authentication methods available")
	}

	hostKeyCallback, hkErr := fb.getKnownHostsCallback(host, hostname, port)
	if hkErr != nil {
		return nil, nil, fmt.Errorf("failed to setup host key verification: %v", hkErr)
	}

	config := &ssh.ClientConfig{
		User:            user,
		Auth:            authMethods,
		HostKeyCallback: hostKeyCallback,
		Timeout:         30 * time.Second,
	}

	return config, nil, nil
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

	// Clear remote selections
	fb.selectedRemoteFiles = fb.selectedRemoteFiles[:0]
	fb.updateSCPButtonState()
	fb.updateDownloadButtonState()
}

func (fb *FileBrowser) createLocalPanel() fyne.CanvasObject {
	leftPanel := container.NewBorder(
		widget.NewLabel("📁 Local Folders"),
		nil, nil, nil,
		fb.folderTree,
	)

	// Sort header for local files
	sortHeader := container.NewHBox(
		widget.NewLabel("Sort:"),
		fb.localNameBtn,
		fb.localSizeBtn,
		fb.localDateBtn,
		widget.NewSeparator(),
		fb.showLocalHidden,
	)

	rightPanel := container.NewBorder(
		container.NewVBox(
			widget.NewLabel("📋 Local Files (Check files to upload)"),
			sortHeader,
		),
		nil, nil, nil,
		fb.fileList,
	)

	localSplit := container.NewHSplit(leftPanel, rightPanel)
	localSplit.SetOffset(0.3)

	return container.NewBorder(
		container.NewHBox(
			fb.upButton, fb.homeButton,
			widget.NewSeparator(),
			widget.NewLabel("Local Path:"), fb.pathLabel,
			widget.NewSeparator(),
			fb.scpUploadBtn,
			fb.deleteLocalBtn,
		),
		fb.statusLabel,
		nil, nil,
		localSplit,
	)
}

func (fb *FileBrowser) createRemotePanel() fyne.CanvasObject {
	showHostsBtn := widget.NewButton("Show Hosts", fb.showAvailableHosts)

	// Create fixed-width entry containers
	charWidth := float32(7.0)
	entryWidth := charWidth * 40

	hostContainer := container.NewHBox(
		widget.NewLabel("Host:"),
		container.NewGridWrap(fyne.NewSize(entryWidth, 36), fb.hostEntry),
	)

	userContainer := container.NewHBox(
		widget.NewLabel("User:"),
		container.NewGridWrap(fyne.NewSize(entryWidth*0.5, 36), fb.userEntry),
	)

	passContainer := container.NewHBox(
		widget.NewLabel("Pass:"),
		container.NewGridWrap(fyne.NewSize(entryWidth*0.5, 36), fb.passEntry),
	)

	keyContainer := container.NewHBox(
		widget.NewLabel("Key:"),
		container.NewGridWrap(fyne.NewSize(entryWidth*0.8, 36), fb.keyEntry),
		fb.keyBrowseBtn,
	)

	settingsBox := container.NewHBox(
		container.NewGridWrap(fyne.NewSize(180, 36), fb.savedSettingsSelect),
		fb.saveSettingsBtn,
		fb.loadSettingsBtn,
		fb.clearSettingsBtn,
		fb.deleteSettingsBtn,
	)

	connectionBox := container.NewVBox(
		container.NewHBox(
			fb.useConfigCheck,
			hostContainer,
			showHostsBtn,
			settingsBox,
		),
		widget.NewSeparator(),
		container.NewHBox(
			userContainer,
			passContainer,
			keyContainer,
			fb.connectButton,
			fb.terminalBtn,
                	widget.NewSeparator(),
                	fb.teleportHelpBtn,
		),
	)

	// Sort header for remote files
	remoteSortHeader := container.NewHBox(
		widget.NewLabel("Sort:"),
		fb.remoteNameBtn,
		fb.remoteSizeBtn,
		fb.remoteDateBtn,
		widget.NewSeparator(),
		fb.showRemoteHidden,
	)

	// Navigation bar with editable path
	navBar := container.NewBorder(
		nil, nil,
		container.NewHBox(
			fb.remoteUpButton,
			fb.remoteHomeButton,
			widget.NewSeparator(),
			widget.NewLabel("Path:"),
		),
		container.NewHBox(
			widget.NewButtonWithIcon("Go", theme.NavigateNextIcon(), func() {
				if fb.sshConn.connected && fb.remotePathEntry.Text != "" {
					fb.RemoteNavigateTo(fb.remotePathEntry.Text)
				}
			}),
		),
		fb.remotePathEntry,
	)

	filePanel := container.NewBorder(
		container.NewVBox(
			widget.NewLabel("📋 Remote Files (Check files to download)"),
			remoteSortHeader,
		),
		nil, nil, nil,
		fb.remoteFileList,
	)

	return container.NewBorder(
		connectionBox,
		container.NewHBox(
			fb.scpDownloadBtn,
			fb.deleteRemoteBtn,
			widget.NewSeparator(),
			fb.remoteStatusLabel,
		),
		nil, nil,
		container.NewBorder(
			navBar,
			nil,
			nil, nil,
			filePanel,
		),
	)
}

func (fb *FileBrowser) getTreeChildren(uid widget.TreeNodeID) []widget.TreeNodeID {
	path := string(uid)

	if path == "" {
		var roots []widget.TreeNodeID
		if homeDir, err := os.UserHomeDir(); err == nil {
			roots = append(roots, widget.TreeNodeID(homeDir))
		}
		roots = append(roots, widget.TreeNodeID(filepath.VolumeName(fb.currentPath)+string(filepath.Separator)))
		commonDirs := []string{"/", "/home", "/usr", "/var", "/tmp"}
		for _, dir := range commonDirs {
			if _, err := os.Stat(dir); err == nil {
				roots = append(roots, widget.TreeNodeID(dir))
			}
		}
		return roots
	}

	dirs := fb.getDirectories(path)
	var children []widget.TreeNodeID
	for _, dir := range dirs {
		children = append(children, widget.TreeNodeID(filepath.Join(path, dir)))
	}

	return children
}

func (fb *FileBrowser) getDirectories(path string) []string {
	if cached, exists := fb.treeData[path]; exists {
		return cached
	}

	entries, err := os.ReadDir(path)
	if err != nil {
		return []string{}
	}

	var dirs []string
	for _, entry := range entries {
		if entry.IsDir() {
			dirs = append(dirs, entry.Name())
		}
	}

	sort.Strings(dirs)
	fb.treeData[path] = dirs
	return dirs
}

func (fb *FileBrowser) NavigateTo(path string) {
	cleanPath := filepath.Clean(path)

	info, err := os.Stat(cleanPath)
	if err != nil {
		fb.statusLabel.SetText(fmt.Sprintf("Local Error: %v", err))
		return
	}

	if !info.IsDir() {
		fb.statusLabel.SetText("Local Error: Not a directory")
		return
	}

	entries, err := os.ReadDir(cleanPath)
	if err != nil {
		fb.statusLabel.SetText(fmt.Sprintf("Local Error: %v", err))
		return
	}

	sort.Slice(entries, func(i, j int) bool {
		if entries[i].IsDir() && !entries[j].IsDir() {
			return true
		}
		if !entries[i].IsDir() && entries[j].IsDir() {
			return false
		}
		return strings.ToLower(entries[i].Name()) < strings.ToLower(entries[j].Name())
	})

	fb.currentPath = cleanPath
	fb.files = entries
	fb.pathLabel.SetText(cleanPath)

	fb.selectedFiles = fb.selectedFiles[:0]
	fb.updateSCPButtonState()

	delete(fb.treeData, cleanPath)

	fileCount := 0
	dirCount := 0
	for _, entry := range entries {
		if entry.IsDir() {
			dirCount++
		} else {
			fileCount++
		}
	}
	fb.statusLabel.SetText(fmt.Sprintf("Local: %d directories, %d files", dirCount, fileCount))

	fb.fileList.Refresh()
	fb.folderTree.Refresh()
}

func (fb *FileBrowser) RemoteNavigateTo(path string) {
	if !fb.sshConn.connected {
		return
	}

	fb.remoteStatusLabel.SetText("Loading directory...")

	go func() {
		files, err := fb.sshConn.sftpClient.ReadDir(path)
		if err != nil {
			fb.remoteStatusLabel.SetText(fmt.Sprintf("Remote Error: %v", err))
			return
		}

		var remoteFiles []RemoteFile
		for _, file := range files {
			remoteFiles = append(remoteFiles, RemoteFile{
				Name:    file.Name(),
				Size:    file.Size(),
				ModTime: file.ModTime(),
				IsDir:   file.IsDir(),
			})
		}

		fb.remoteCurrentPath = path
		fb.remoteFiles = remoteFiles
		fb.remotePathEntry.SetText(path)

		// Apply sort
		fb.applySortToRemoteFiles()

		// Clear selections when navigating
		fb.selectedRemoteFiles = fb.selectedRemoteFiles[:0]
		fb.updateDownloadButtonState()

		visibleFiles := fb.getVisibleRemoteFiles()
		fileCount := 0
		dirCount := 0
		for _, file := range visibleFiles {
			if file.IsDir {
				dirCount++
			} else {
				fileCount++
			}
		}

		fb.remoteStatusLabel.SetText(fmt.Sprintf("Remote: %d directories, %d files", dirCount, fileCount))

		fb.remoteFileList.Refresh()
		fb.remoteFileList.UnselectAll()
	}()
}

func (fb *FileBrowser) loadPrivateKey(keyPath string) (ssh.Signer, error) {
	keyData, err := os.ReadFile(keyPath)
	if err != nil {
		return nil, err
	}

	key, err := ssh.ParsePrivateKey(keyData)
	if err != nil {
		if fb.passEntry.Text != "" {
			key, err = ssh.ParsePrivateKeyWithPassphrase(keyData, []byte(fb.passEntry.Text))
		}
	}

	return key, err
}

func (fb *FileBrowser) showAvailableHosts() {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		dialog.ShowError(fmt.Errorf("could not find home directory: %v", err), fb.mainWindow)
		return
	}

	configPath := filepath.Join(homeDir, ".ssh", "config")

	content, err := os.ReadFile(configPath)
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

func extractHostsFromConfig(content string) []string {
	var hosts []string
	lines := strings.Split(content, "\n")

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		if strings.HasPrefix(strings.ToLower(line), "host ") {
			hostLine := strings.TrimPrefix(line, "host ")
			hostLine = strings.TrimPrefix(hostLine, "Host ")

			hostPatterns := strings.Fields(hostLine)

			for _, pattern := range hostPatterns {
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

func formatFileSize(size int64) string {
	const unit = 1024
	if size < unit {
		return fmt.Sprintf("%d B", size)
	}
	div, exp := int64(unit), 0
	for n := size / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(size)/float64(div), "KMGTPE"[exp])
}
