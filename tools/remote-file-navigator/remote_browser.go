package main

import (
	"fmt"
	"path/filepath"
	"strings"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/theme"
	"fyne.io/fyne/v2/widget"
)

func (fb *FileBrowser) initializeRemoteBrowser() {
	fb.remoteStatusLabel = widget.NewLabel("Remote: Not connected")
	fb.remoteCurrentPath = "/"

	fb.remotePathEntry = widget.NewEntry()
	fb.remotePathEntry.SetPlaceHolder("/path/to/directory")
	fb.remotePathEntry.SetText("/")
	fb.remotePathEntry.OnSubmitted = func(path string) {
		if fb.sshConn.connected && path != "" {
			fb.RemoteNavigateTo(path)
		}
	}

	fb.showRemoteHidden = widget.NewCheck("Show Hidden", func(checked bool) {
		fb.remoteFileList.Refresh()
	})

	fb.remoteNameBtn = widget.NewButton("Name ▲", func() { fb.sortRemoteFiles("name") })
	fb.remoteSizeBtn = widget.NewButton("Size", func() { fb.sortRemoteFiles("size") })
	fb.remoteDateBtn = widget.NewButton("Date", func() { fb.sortRemoteFiles("date") })

	fb.remoteFileList = widget.NewList(
		func() int { return len(fb.getVisibleRemoteFiles()) },
		func() fyne.CanvasObject {
			return container.NewHBox(
				widget.NewCheck("", nil),
				container.NewGridWrap(fyne.NewSize(250, 20), widget.NewLabel("Template Remote File Name")),
				container.NewGridWrap(fyne.NewSize(80, 20), widget.NewLabel("999.9 MB")),
				container.NewGridWrap(fyne.NewSize(120, 20), widget.NewLabel("2024-01-01 00:00")),
			)
		},
		func(id widget.ListItemID, item fyne.CanvasObject) {
			files := fb.getVisibleRemoteFiles()
			if id >= len(files) {
				return
			}
			fb.updateRemoteFileListItem(id, item, files[id])
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
			fb.remoteStatusLabel.SetText(fmt.Sprintf("Selected: %s (%s)", file.Name, formatFileSize(file.Size)))
		}
	}

	fb.remoteUpButton = widget.NewButtonWithIcon("Up", theme.NavigateBackIcon(), func() {
		if !fb.sshConn.connected {
			return
		}
		if parentDir := filepath.Dir(fb.remoteCurrentPath); parentDir != fb.remoteCurrentPath && parentDir != "." {
			fb.RemoteNavigateTo(parentDir)
		}
	})

	fb.remoteHomeButton = widget.NewButtonWithIcon("Home", theme.HomeIcon(), func() {
		if fb.sshConn.connected {
			homeDir, err := fb.getRemoteHomeDir()
			if err != nil || homeDir == "" {
				homeDir = "/"
			}
			fb.RemoteNavigateTo(homeDir)
		}
	})

	fb.scpDownloadBtn = widget.NewButtonWithIcon("Download ⬇", theme.DownloadIcon(), fb.scpDownloadFiles)
	fb.scpDownloadBtn.Disable()

	fb.deleteRemoteBtn = widget.NewButtonWithIcon("Delete", theme.DeleteIcon(), fb.confirmDeleteRemoteFiles)
	fb.deleteRemoteBtn.Disable()
}

func (fb *FileBrowser) updateRemoteFileListItem(id widget.ListItemID, item fyne.CanvasObject, file RemoteFile) {
	box := item.(*fyne.Container)
	check := box.Objects[0].(*widget.Check)
	nameLabel := box.Objects[1].(*fyne.Container).Objects[0].(*widget.Label)
	sizeLabel := box.Objects[2].(*fyne.Container).Objects[0].(*widget.Label)
	dateLabel := box.Objects[3].(*fyne.Container).Objects[0].(*widget.Label)

	icon := "📄 "
	sizeStr := formatFileSize(file.Size)
	if file.IsDir {
		icon = "📁 "
		sizeStr = "<DIR>"
	}

	nameLabel.SetText(icon + file.Name)
	sizeLabel.SetText(sizeStr)
	dateLabel.SetText(file.ModTime.Format("2006-01-02 15:04"))

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

		fb.applySortToRemoteFiles()
		fb.selectedRemoteFiles = fb.selectedRemoteFiles[:0]
		fb.updateDownloadButtonState()

		visibleFiles := fb.getVisibleRemoteFiles()
		var fileCount, dirCount int
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
