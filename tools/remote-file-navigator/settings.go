package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/widget"
)

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
	data, err := os.ReadFile(fb.getSettingsFilePath())
	if err != nil {
		if os.IsNotExist(err) {
			return &SSHSettingsStore{Settings: []SSHSettings{}}, nil
		}
		return nil, err
	}

	var store SSHSettingsStore
	if err := json.Unmarshal(data, &store); err != nil {
		return nil, err
	}
	return &store, nil
}

func (fb *FileBrowser) saveSettingsStore(store *SSHSettingsStore) error {
	data, err := json.MarshalIndent(store, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(fb.getSettingsFilePath(), data, 0600)
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

	nameEntry := widget.NewEntry()
	nameEntry.SetPlaceHolder("Connection name")
	nameEntry.SetText(fb.hostEntry.Text)

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

	if err := fb.saveSettingsStore(store); err != nil {
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

	if store.LastUsed != "" {
		fb.onSavedSettingSelected(store.LastUsed)
		return
	}

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

	var newSettings []SSHSettings
	for _, s := range store.Settings {
		if s.Name != name {
			newSettings = append(newSettings, s)
		}
	}
	store.Settings = newSettings

	if store.LastUsed == name {
		store.LastUsed = ""
		if len(store.Settings) > 0 {
			store.LastUsed = store.Settings[0].Name
		}
	}

	if err := fb.saveSettingsStore(store); err != nil {
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
				if err := os.Remove(settingsPath); err != nil {
					dialog.ShowError(fmt.Errorf("failed to delete settings: %v", err), fb.mainWindow)
					return
				}
				fb.refreshSavedSettingsDropdown()
				fb.remoteStatusLabel.SetText("✅ Saved settings deleted")
			}
		}, fb.mainWindow)
}
