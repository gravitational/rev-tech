package main

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/theme"
	"fyne.io/fyne/v2/widget"
)

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

	fb.showLocalHidden = widget.NewCheck("Show Hidden", func(checked bool) {
		fb.fileList.Refresh()
	})

	fb.localNameBtn = widget.NewButton("Name ▲", func() { fb.sortLocalFiles("name") })
	fb.localSizeBtn = widget.NewButton("Size", func() { fb.sortLocalFiles("size") })
	fb.localDateBtn = widget.NewButton("Date", func() { fb.sortLocalFiles("date") })

	fb.folderTree = widget.NewTree(
		func(uid widget.TreeNodeID) []widget.TreeNodeID { return fb.getTreeChildren(uid) },
		func(uid widget.TreeNodeID) bool {
			path := string(uid)
			if path == "" {
				return true
			}
			return len(fb.getDirectories(path)) > 0
		},
		func(branch bool) fyne.CanvasObject { return widget.NewLabel("📁 Folder") },
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
			item.(*widget.Label).SetText("📁 " + name)
		},
	)

	fb.folderTree.OnSelected = func(uid widget.TreeNodeID) {
		if path := string(uid); path != "" {
			fb.NavigateTo(path)
		}
	}

	fb.fileList = widget.NewList(
		func() int { return len(fb.getVisibleLocalFiles()) },
		func() fyne.CanvasObject {
			return container.NewHBox(
				widget.NewCheck("", nil),
				container.NewGridWrap(fyne.NewSize(250, 20), widget.NewLabel("Template File Name")),
				container.NewGridWrap(fyne.NewSize(80, 20), widget.NewLabel("999.9 MB")),
				container.NewGridWrap(fyne.NewSize(120, 20), widget.NewLabel("2024-01-01 00:00")),
			)
		},
		func(id widget.ListItemID, item fyne.CanvasObject) {
			files := fb.getVisibleLocalFiles()
			if id >= len(files) {
				return
			}
			fb.updateLocalFileListItem(id, item, files[id])
		},
	)

	fb.fileList.OnSelected = func(id widget.ListItemID) {
		files := fb.getVisibleLocalFiles()
		if id >= len(files) {
			return
		}
		if entry := files[id]; entry.IsDir() {
			newPath := filepath.Join(fb.currentPath, entry.Name())
			fb.NavigateTo(newPath)
			fb.folderTree.Select(widget.TreeNodeID(newPath))
		}
	}

	fb.upButton = widget.NewButtonWithIcon("Up", theme.NavigateBackIcon(), func() {
		if parentDir := filepath.Dir(fb.currentPath); parentDir != fb.currentPath {
			fb.NavigateTo(parentDir)
			fb.folderTree.Select(widget.TreeNodeID(parentDir))
		}
	})

	fb.homeButton = widget.NewButtonWithIcon("Home", theme.HomeIcon(), func() {
		if homeDir, err := os.UserHomeDir(); err == nil {
			fb.NavigateTo(homeDir)
			fb.folderTree.Select(widget.TreeNodeID(homeDir))
		}
	})

	fb.scpUploadBtn = widget.NewButtonWithIcon("Upload ⬆", theme.UploadIcon(), fb.scpUploadFiles)
	fb.scpUploadBtn.Disable()

	fb.deleteLocalBtn = widget.NewButtonWithIcon("Delete", theme.DeleteIcon(), fb.confirmDeleteLocalFiles)
	fb.deleteLocalBtn.Disable()
}

func (fb *FileBrowser) updateLocalFileListItem(id widget.ListItemID, item fyne.CanvasObject, entry fs.DirEntry) {
	box := item.(*fyne.Container)
	check := box.Objects[0].(*widget.Check)
	nameLabel := box.Objects[1].(*fyne.Container).Objects[0].(*widget.Label)
	sizeLabel := box.Objects[2].(*fyne.Container).Objects[0].(*widget.Label)
	dateLabel := box.Objects[3].(*fyne.Container).Objects[0].(*widget.Label)

	icon := "📄 "
	if entry.IsDir() {
		icon = "📁 "
	}

	var sizeStr, dateStr string
	if info, _ := entry.Info(); info != nil {
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

func (fb *FileBrowser) getTreeChildren(uid widget.TreeNodeID) []widget.TreeNodeID {
	path := string(uid)
	if path == "" {
		var roots []widget.TreeNodeID
		if homeDir, err := os.UserHomeDir(); err == nil {
			roots = append(roots, widget.TreeNodeID(homeDir))
		}
		roots = append(roots, widget.TreeNodeID(filepath.VolumeName(fb.currentPath)+string(filepath.Separator)))
		for _, dir := range []string{"/", "/home", "/usr", "/var", "/tmp"} {
			if _, err := os.Stat(dir); err == nil {
				roots = append(roots, widget.TreeNodeID(dir))
			}
		}
		return roots
	}

	var children []widget.TreeNodeID
	for _, dir := range fb.getDirectories(path) {
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

	var fileCount, dirCount int
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
