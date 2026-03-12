package main

import (
	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/theme"
	"fyne.io/fyne/v2/widget"
)

func (fb *FileBrowser) createLocalPanel() fyne.CanvasObject {
	leftPanel := container.NewBorder(
		widget.NewLabel("📁 Local Folders"),
		nil, nil, nil,
		fb.folderTree,
	)

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

	remoteSortHeader := container.NewHBox(
		widget.NewLabel("Sort:"),
		fb.remoteNameBtn,
		fb.remoteSizeBtn,
		fb.remoteDateBtn,
		widget.NewSeparator(),
		fb.showRemoteHidden,
	)

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
