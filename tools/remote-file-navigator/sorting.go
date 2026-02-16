package main

import (
	"sort"
	"strings"
)

// Local file sorting
func (fb *FileBrowser) sortLocalFiles(column string) {
	if fb.localSortColumn == column {
		fb.localSortAsc = !fb.localSortAsc
	} else {
		fb.localSortColumn = column
		fb.localSortAsc = true
	}

	fb.updateLocalSortButtons()
	fb.applySortToLocalFiles()
	fb.fileList.Refresh()
}

func (fb *FileBrowser) updateLocalSortButtons() {
	fb.localNameBtn.SetText("Name")
	fb.localSizeBtn.SetText("Size")
	fb.localDateBtn.SetText("Date")

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

func (fb *FileBrowser) applyLocalFilter() {
	fb.applySortToLocalFiles()
}

// Remote file sorting
func (fb *FileBrowser) sortRemoteFiles(column string) {
	if fb.remoteSortColumn == column {
		fb.remoteSortAsc = !fb.remoteSortAsc
	} else {
		fb.remoteSortColumn = column
		fb.remoteSortAsc = true
	}

	fb.updateRemoteSortButtons()
	fb.applySortToRemoteFiles()
	fb.remoteFileList.Refresh()
}

func (fb *FileBrowser) updateRemoteSortButtons() {
	fb.remoteNameBtn.SetText("Name")
	fb.remoteSizeBtn.SetText("Size")
	fb.remoteDateBtn.SetText("Date")

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

func (fb *FileBrowser) applyRemoteFilter() {
	fb.applySortToRemoteFiles()
}
