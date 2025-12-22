package main

import (
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
	"fyne.io/fyne/v2/widget"
	"fyne.io/fyne/v2/theme"

	"golang.org/x/crypto/ssh"
	"golang.org/x/crypto/ssh/agent"
	"github.com/pkg/sftp"
	"github.com/kevinburke/ssh_config"
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
	currentPath    string
	fileList       *widget.List
	folderTree     *widget.Tree
	pathLabel      *widget.Label
	upButton       *widget.Button
	homeButton     *widget.Button
	scpUploadBtn   *widget.Button
	deleteLocalBtn *widget.Button
	files          []fs.DirEntry
	statusLabel    *widget.Label
	treeData       map[string][]string
	selectedFiles  []string

	// Remote SSH browser
	sshConn             *SSHConnection
	remoteCurrentPath   string
	remoteFileList      *widget.List
	remoteFolderTree    *widget.Tree
	remotePathLabel     *widget.Label
	remoteUpButton      *widget.Button
	remoteHomeButton    *widget.Button
	remoteFiles         []RemoteFile
	remoteStatusLabel   *widget.Label
	remoteTreeData      map[string][]string
	selectedRemoteFiles []string
	scpDownloadBtn      *widget.Button
	deleteRemoteBtn     *widget.Button

	// SSH connection controls
	hostEntry     *widget.Entry
	userEntry     *widget.Entry
	passEntry     *widget.Entry
	keyEntry      *widget.Entry
	connectButton *widget.Button
	terminalBtn   *widget.Button
	useConfigCheck *widget.Check
	saveSettingsBtn *widget.Button
	loadSettingsBtn *widget.Button
	clearSettingsBtn *widget.Button
	deleteSettingsBtn *widget.Button
	savedSettingsSelect *widget.Select
	
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
	myWindow := myApp.NewWindow("Remote System File Browser")
	myWindow.Resize(fyne.NewSize(1200, 900))

	browser := NewFileBrowser(myWindow)
	
	// Start in the current directory for local browser
	currentDir, _ := os.Getwd()
	browser.NavigateTo(currentDir)

	// Create main layout with local and remote panels
	localPanel := browser.createLocalPanel()
	remotePanel := browser.createRemotePanel()
	
	// Create horizontal split: local on left, remote on right
	mainSplit := container.NewHSplit(localPanel, remotePanel)
	mainSplit.SetOffset(0.5) // 50% for local, 50% for remote

	// Create the main layout
	content := container.NewBorder(
		widget.NewLabel("🔗 Local & Remote File Browser"), // top
		widget.NewLabel("Ready"), // bottom
		nil,                       // left
		nil,                       // right
		mainSplit,                 // center
	)

	myWindow.SetContent(content)
	myWindow.ShowAndRun()
}

func NewFileBrowser(window fyne.Window) *FileBrowser {
	browser := &FileBrowser{
		treeData:            make(map[string][]string),
		remoteTreeData:      make(map[string][]string),
		sshConn:             &SSHConnection{},
		mainWindow:          window,
		selectedFiles:       make([]string, 0),
		selectedRemoteFiles: make([]string, 0),
	}
	
	browser.initializeLocalBrowser()
	browser.initializeRemoteBrowser()
	browser.initializeSSHControls()

	return browser
}

func (fb *FileBrowser) initializeLocalBrowser() {
	fb.pathLabel = widget.NewLabel("")
	fb.statusLabel = widget.NewLabel("Local: Ready")
	
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
		func() int { return len(fb.files) },
		func() fyne.CanvasObject { 
			check := widget.NewCheck("", nil)
			label := widget.NewLabel("Template File")
			return container.NewHBox(check, label)
		},
		func(id widget.ListItemID, item fyne.CanvasObject) {
			if id >= len(fb.files) {
				return
			}
			
			entry := fb.files[id]
			box := item.(*fyne.Container)
			check := box.Objects[0].(*widget.Check)
			label := box.Objects[1].(*widget.Label)
			
			var icon string
			if entry.IsDir() {
				icon = "📁"
			} else {
				icon = "📄"
			}
			
			info, _ := entry.Info()
			var sizeStr string
			if entry.IsDir() {
				sizeStr = "<DIR>"
			} else {
				sizeStr = formatFileSize(info.Size())
			}
			
			label.SetText(fmt.Sprintf("%s %-45s %12s", icon, entry.Name(), sizeStr))
			
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
		if id >= len(fb.files) {
			return
		}
		
		entry := fb.files[id]
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
	fb.remotePathLabel = widget.NewLabel("")
	fb.remoteStatusLabel = widget.NewLabel("Remote: Not connected")
	fb.remoteCurrentPath = "/"
	
	// Create remote folder tree
	fb.remoteFolderTree = widget.NewTree(
		func(uid widget.TreeNodeID) []widget.TreeNodeID {
			return fb.getRemoteTreeChildren(uid)
		},
		func(uid widget.TreeNodeID) bool {
			path := string(uid)
			if path == "" || !fb.sshConn.connected {
				return false
			}
			children := fb.getRemoteDirectories(path)
			return len(children) > 0
		},
		func(branch bool) fyne.CanvasObject {
			return widget.NewLabel("🌐 Remote Folder")
		},
		func(uid widget.TreeNodeID, branch bool, item fyne.CanvasObject) {
			path := string(uid)
			var name string
			if path == "" || path == "/" {
				name = "🖥️ " + fb.sshConn.host
			} else {
				name = filepath.Base(path)
			}
			
			label := item.(*widget.Label)
			label.SetText("🌐 " + name)
		},
	)
	
	fb.remoteFolderTree.OnSelected = func(uid widget.TreeNodeID) {
		path := string(uid)
		if path != "" && fb.sshConn.connected {
			fb.RemoteNavigateTo(path)
		}
	}

	// Create remote file list with selection support
	fb.remoteFileList = widget.NewList(
		func() int { return len(fb.remoteFiles) },
		func() fyne.CanvasObject { 
			check := widget.NewCheck("", nil)
			label := widget.NewLabel("Template Remote File")
			return container.NewHBox(check, label)
		},
		func(id widget.ListItemID, item fyne.CanvasObject) {
			if id >= len(fb.remoteFiles) {
				return
			}
			
			file := fb.remoteFiles[id]
			box := item.(*fyne.Container)
			check := box.Objects[0].(*widget.Check)
			label := box.Objects[1].(*widget.Label)
			
			var icon string
			var typeInfo string
			if file.IsDir {
				icon = "📁"
				typeInfo = "<DIR>"
			} else {
				icon = "📄"
				typeInfo = formatFileSize(file.Size)
			}
			
			modTime := file.ModTime.Format("2006-01-02 15:04")
			label.SetText(fmt.Sprintf("%s %-35s %10s %s", 
				icon, file.Name, typeInfo, modTime))
			
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
		if id >= len(fb.remoteFiles) || !fb.sshConn.connected {
			return
		}
		
		file := fb.remoteFiles[id]
		if file.IsDir {
			var newPath string
			if fb.remoteCurrentPath == "/" {
				newPath = "/" + file.Name
			} else {
				newPath = fb.remoteCurrentPath + "/" + file.Name
			}
			
			fb.RemoteNavigateTo(newPath)
			fb.remoteFolderTree.Select(widget.TreeNodeID(newPath))
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
				fb.remoteFolderTree.Select(widget.TreeNodeID(parentDir))
			}
		})

	fb.remoteHomeButton = widget.NewButtonWithIcon("Home", theme.HomeIcon(),
		func() {
			if fb.sshConn.connected {
				fb.RemoteNavigateTo("/")
				fb.remoteFolderTree.Select(widget.TreeNodeID("/"))
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
	
	fb.hostEntry.OnChanged = func(text string) {
		if fb.useConfigCheck.Checked && text != "" {
			fb.previewSSHConfig(text)
		}
	}
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
	
	fb.statusLabel.SetText(fmt.Sprintf("Starting SCP upload of %d file(s)...", len(fb.selectedFiles)))
	
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
			fb.statusLabel.SetText(fmt.Sprintf("✅ SCP uploaded %d file(s) successfully", uploaded))
		} else {
			fb.statusLabel.SetText(fmt.Sprintf("⚠️ SCP uploaded %d file(s), %d failed", uploaded, failed))
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
	
	fb.remoteStatusLabel.SetText(fmt.Sprintf("Starting SCP download of %d file(s)...", len(fb.selectedRemoteFiles)))
	
	go func() {
		downloaded := 0
		failed := 0
		skipped := 0
		
		for i, remotePath := range fb.selectedRemoteFiles {
			filename := filepath.Base(remotePath)
			fb.remoteStatusLabel.SetText(fmt.Sprintf("SCP downloading %d/%d: %s", i+1, len(fb.selectedRemoteFiles), filename))
			
			// Check if it's a directory
			info, err := fb.sshConn.sftpClient.Stat(remotePath)
			if err != nil {
				fmt.Printf("SCP download failed for %s: %v\n", remotePath, err)
				failed++
				continue
			}
			
			if info.IsDir() {
				fmt.Printf("Skipping directory: %s\n", remotePath)
				skipped++
				continue
			}
			
			err = fb.scpDownloadFile(remotePath)
			if err != nil {
				fmt.Printf("SCP download failed for %s: %v\n", remotePath, err)
				failed++
			} else {
				downloaded++
			}
		}
		
		var statusMsg string
		if failed == 0 && skipped == 0 {
			statusMsg = fmt.Sprintf("✅ SCP downloaded %d file(s) successfully to %s", downloaded, fb.currentPath)
		} else if skipped > 0 {
			statusMsg = fmt.Sprintf("✅ Downloaded %d, ⏭️ skipped %d dirs, ❌ %d failed", downloaded, skipped, failed)
		} else {
			statusMsg = fmt.Sprintf("⚠️ SCP downloaded %d file(s), %d failed", downloaded, failed)
		}
		fb.remoteStatusLabel.SetText(statusMsg)
		
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
	
	// Build SCP command arguments
	var scpArgs []string
	
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
	
	if stat.IsDir() {
		return fmt.Errorf("directory upload not supported via SCP")
	}
	
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
		fb.remoteFolderTree.Refresh()
	}()
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

	config := &ssh.ClientConfig{
		User:            user,
		Auth:            authMethods,
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         30 * time.Second,
	}

	var conn net.Conn
	var err error
	
	if proxyJump != "" {
		conn, err = fb.connectViaProxyJump(proxyJump, hostname, port, config)
		if err != nil {
			return nil, nil, fmt.Errorf("ProxyJump failed: %v", err)
		}
		return config, conn, nil
	} else if proxyCommand != "" && proxyCommand != "none" {
		conn, err = fb.connectViaProxyCommand(proxyCommand, hostname, port)
		if err != nil {
			return nil, nil, fmt.Errorf("ProxyCommand failed: %v", err)
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
	
	proxyClient, err := ssh.Dial("tcp", proxyHostname+":"+proxyPort, proxyConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to proxy %s: %v", proxyHost, err)
	}
	
	targetAddr := targetHost + ":" + targetPort
	conn, err := proxyClient.Dial("tcp", targetAddr)
	if err != nil {
		proxyClient.Close()
		return nil, fmt.Errorf("failed to connect through proxy to %s: %v", targetAddr, err)
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
	
	go func() {
		buf := make([]byte, 1024)
		for {
			_, err := stderr.Read(buf)
			if err != nil {
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

	var authMethods []ssh.AuthMethod

	if sshAuthSock := os.Getenv("SSH_AUTH_SOCK"); sshAuthSock != "" {
		if agentConn, err := net.Dial("unix", sshAuthSock); err == nil {
			agentClient := agent.NewClient(agentConn)
			authMethods = append(authMethods, ssh.PublicKeysCallback(agentClient.Signers))
		}
	}

	if fb.keyEntry.Text != "" {
		if key, err := fb.loadPrivateKey(fb.keyEntry.Text); err == nil {
			authMethods = append(authMethods, ssh.PublicKeys(key))
		}
	}

	if pass != "" {
		authMethods = append(authMethods, ssh.Password(pass))
	}

	if len(authMethods) == 0 {
		return nil, nil, fmt.Errorf("no authentication methods available")
	}

	config := &ssh.ClientConfig{
		User:            user,
		Auth:            authMethods,
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
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
	fb.remoteFolderTree.Refresh()
	
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
	
	rightPanel := container.NewBorder(
		widget.NewLabel("📋 Local Files (Check files to upload)"),
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
	
	// Create fixed-width entry containers (40 chars ≈ 280 pixels with default font)
	charWidth := float32(7.0) // approximate width per character
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
		container.NewGridWrap(fyne.NewSize(entryWidth, 36), fb.keyEntry),
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
		),
	)
	
	leftPanel := container.NewBorder(
		widget.NewLabel("🌐 Remote Folders"),
		nil, nil, nil,
		fb.remoteFolderTree,
	)
	
	rightPanel := container.NewBorder(
		widget.NewLabel("📋 Remote Files (Check files to download)"),
		nil, nil, nil,
		fb.remoteFileList,
	)
	
	remoteSplit := container.NewHSplit(leftPanel, rightPanel)
	remoteSplit.SetOffset(0.3)
	
	return container.NewBorder(
		connectionBox,
		container.NewHBox(
			fb.remoteUpButton, fb.remoteHomeButton, 
			widget.NewSeparator(), 
			widget.NewLabel("Remote Path:"), fb.remotePathLabel,
			widget.NewSeparator(),
			fb.scpDownloadBtn,
			fb.deleteRemoteBtn,
		),
		nil, nil,
		container.NewBorder(
			nil,
			fb.remoteStatusLabel,
			nil, nil,
			remoteSplit,
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

func (fb *FileBrowser) getRemoteTreeChildren(uid widget.TreeNodeID) []widget.TreeNodeID {
	if !fb.sshConn.connected {
		return []widget.TreeNodeID{}
	}
	
	path := string(uid)
	if path == "" {
		return []widget.TreeNodeID{widget.TreeNodeID("/")}
	}
	
	dirs := fb.getRemoteDirectories(path)
	var children []widget.TreeNodeID
	for _, dir := range dirs {
		var childPath string
		if path == "/" {
			childPath = "/" + dir
		} else {
			childPath = path + "/" + dir
		}
		children = append(children, widget.TreeNodeID(childPath))
	}
	
	return children
}

func (fb *FileBrowser) getRemoteDirectories(path string) []string {
	if !fb.sshConn.connected {
		return []string{}
	}
	
	if cached, exists := fb.remoteTreeData[path]; exists {
		return cached
	}
	
	files, err := fb.sshConn.sftpClient.ReadDir(path)
	if err != nil {
		return []string{}
	}
	
	var dirs []string
	for _, file := range files {
		if file.IsDir() {
			dirs = append(dirs, file.Name())
		}
	}
	
	sort.Strings(dirs)
	fb.remoteTreeData[path] = dirs
	return dirs
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

		sort.Slice(remoteFiles, func(i, j int) bool {
			if remoteFiles[i].IsDir && !remoteFiles[j].IsDir {
				return true
			}
			if !remoteFiles[i].IsDir && remoteFiles[j].IsDir {
				return false
			}
			return strings.ToLower(remoteFiles[i].Name) < strings.ToLower(remoteFiles[j].Name)
		})

		fb.remoteCurrentPath = path
		fb.remoteFiles = remoteFiles
		fb.remotePathLabel.SetText(path)
		
		// Clear selections when navigating
		fb.selectedRemoteFiles = fb.selectedRemoteFiles[:0]
		fb.updateDownloadButtonState()
		
		delete(fb.remoteTreeData, path)
		
		fileCount := 0
		dirCount := 0
		for _, file := range remoteFiles {
			if file.IsDir {
				dirCount++
			} else {
				fileCount++
			}
		}
		
		fb.remoteStatusLabel.SetText(fmt.Sprintf("Remote: %d directories, %d files", dirCount, fileCount))
		
		fb.remoteFileList.Refresh()
		fb.remoteFolderTree.Refresh()
		
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
