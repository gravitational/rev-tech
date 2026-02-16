package main

import (
	"fmt"
	"os"
	"path/filepath"

	"fyne.io/fyne/v2/dialog"
)

func (fb *FileBrowser) confirmDeleteLocalFiles() {
	if len(fb.selectedFiles) == 0 {
		return
	}

	msg := fb.buildDeleteConfirmMessage(fb.selectedFiles)
	dialog.ShowConfirm("Confirm Delete", msg, func(confirmed bool) {
		if confirmed {
			fb.deleteLocalFiles()
		}
	}, fb.mainWindow)
}

func (fb *FileBrowser) deleteLocalFiles() {
	deleted, failed := 0, 0

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

	msg := fb.buildDeleteConfirmMessage(fb.selectedRemoteFiles)
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
		deleted, failed := 0, 0

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
	files, err := fb.sshConn.sftpClient.ReadDir(path)
	if err != nil {
		return err
	}

	for _, file := range files {
		fullPath := path + "/" + file.Name()
		if file.IsDir() {
			if err := fb.deleteRemoteDirectory(fullPath); err != nil {
				return err
			}
		} else {
			if err := fb.sshConn.sftpClient.Remove(fullPath); err != nil {
				return err
			}
		}
	}

	return fb.sshConn.sftpClient.RemoveDirectory(path)
}

func (fb *FileBrowser) buildDeleteConfirmMessage(files []string) string {
	if len(files) == 1 {
		return fmt.Sprintf("Are you sure you want to delete:\n%s", filepath.Base(files[0]))
	}

	msg := fmt.Sprintf("Are you sure you want to delete %d items?\n\n", len(files))
	for i, f := range files {
		if i < 5 {
			msg += fmt.Sprintf("• %s\n", filepath.Base(f))
		} else {
			msg += fmt.Sprintf("... and %d more", len(files)-5)
			break
		}
	}
	return msg
}
