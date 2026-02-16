package main

import "fmt"

// Local file selection helpers
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

// Remote file selection helpers
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

// Button state updates
func (fb *FileBrowser) updateSCPButtonState() {
	if len(fb.selectedFiles) > 0 && fb.sshConn.connected {
		fb.scpUploadBtn.Enable()
		fb.scpUploadBtn.SetText(fmt.Sprintf("Upload ⬆ (%d)", len(fb.selectedFiles)))
	} else {
		fb.scpUploadBtn.Disable()
		fb.scpUploadBtn.SetText("Upload ⬆")
	}

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
		fb.scpDownloadBtn.SetText(fmt.Sprintf("Download ⬇ (%d)", len(fb.selectedRemoteFiles)))
		fb.deleteRemoteBtn.Enable()
		fb.deleteRemoteBtn.SetText(fmt.Sprintf("Delete (%d)", len(fb.selectedRemoteFiles)))
	} else {
		fb.scpDownloadBtn.Disable()
		fb.scpDownloadBtn.SetText("Download ⬇")
		fb.deleteRemoteBtn.Disable()
		fb.deleteRemoteBtn.SetText("Delete")
	}
}
