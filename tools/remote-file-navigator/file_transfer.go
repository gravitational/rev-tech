package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"fyne.io/fyne/v2/dialog"
	"github.com/kevinburke/ssh_config"
)

func (fb *FileBrowser) scpUploadFiles() {
	if len(fb.selectedFiles) == 0 {
		fb.statusLabel.SetText("No files selected for upload")
		return
	}

	if !fb.sshConn.connected {
		fb.statusLabel.SetText("Not connected to remote server")
		return
	}

	// Check for directories
	var dirs []string
	for _, filePath := range fb.selectedFiles {
		if info, err := os.Stat(filePath); err == nil && info.IsDir() {
			dirs = append(dirs, filepath.Base(filePath))
		}
	}

	if len(dirs) > 0 {
		msg := fb.buildRecursiveConfirmMessage("upload", dirs)
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
	fb.statusLabel.SetText(fmt.Sprintf("Starting upload of %d item(s)...", len(fb.selectedFiles)))

	go func() {
		uploaded, failed := 0, 0

		for i, filePath := range fb.selectedFiles {
			fb.statusLabel.SetText(fmt.Sprintf("Uploading %d/%d: %s", i+1, len(fb.selectedFiles), filepath.Base(filePath)))

			if err := fb.scpUploadFile(filePath); err != nil {
				fmt.Printf("Upload failed for %s: %v\n", filePath, err)
				failed++
			} else {
				uploaded++
			}
		}

		if failed == 0 {
			fb.statusLabel.SetText(fmt.Sprintf("✅ Uploaded %d item(s) successfully", uploaded))
		} else {
			fb.statusLabel.SetText(fmt.Sprintf("⚠️ Uploaded %d, failed %d", uploaded, failed))
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

	// Check for directories
	var dirs []string
	for _, remotePath := range fb.selectedRemoteFiles {
		if info, err := fb.sshConn.sftpClient.Stat(remotePath); err == nil && info.IsDir() {
			dirs = append(dirs, filepath.Base(remotePath))
		}
	}

	if len(dirs) > 0 {
		msg := fb.buildRecursiveConfirmMessage("download", dirs)
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
	fb.remoteStatusLabel.SetText(fmt.Sprintf("Starting download of %d item(s)...", len(fb.selectedRemoteFiles)))

	go func() {
		downloaded, failed := 0, 0

		for i, remotePath := range fb.selectedRemoteFiles {
			fb.remoteStatusLabel.SetText(fmt.Sprintf("Downloading %d/%d: %s", i+1, len(fb.selectedRemoteFiles), filepath.Base(remotePath)))

			if err := fb.scpDownloadFile(remotePath); err != nil {
				fmt.Printf("Download failed for %s: %v\n", remotePath, err)
				failed++
			} else {
				downloaded++
			}
		}

		if failed == 0 {
			fb.remoteStatusLabel.SetText(fmt.Sprintf("✅ Downloaded %d item(s) to %s", downloaded, fb.currentPath))
		} else {
			fb.remoteStatusLabel.SetText(fmt.Sprintf("⚠️ Downloaded %d, ❌ %d failed", downloaded, failed))
		}

		fb.selectedRemoteFiles = fb.selectedRemoteFiles[:0]
		fb.updateDownloadButtonState()
		fb.remoteFileList.Refresh()
		fb.NavigateTo(fb.currentPath)
	}()
}

func (fb *FileBrowser) scpUploadFile(localPath string) error {
	stat, err := os.Stat(localPath)
	if err != nil {
		return fmt.Errorf("failed to stat file: %v", err)
	}

	filename := filepath.Base(localPath)
	var remoteFilePath string
	if fb.remoteCurrentPath == "/" {
		remoteFilePath = "/" + filename
	} else {
		remoteFilePath = fb.remoteCurrentPath + "/" + filename
	}

	host, user, hostname, port := fb.getSSHParams()
	scpArgs := fb.buildSCPArgs(host, port, stat.IsDir())
	scpArgs = append(scpArgs, localPath, fmt.Sprintf("%s@%s:%s", user, hostname, remoteFilePath))

	return fb.runSCPCommand(scpArgs)
}

func (fb *FileBrowser) scpDownloadFile(remotePath string) error {
	info, err := fb.sshConn.sftpClient.Stat(remotePath)
	if err != nil {
		return fmt.Errorf("failed to stat remote path: %v", err)
	}

	localPath := filepath.Join(fb.currentPath, filepath.Base(remotePath))
	host, user, hostname, port := fb.getSSHParams()
	scpArgs := fb.buildSCPArgs(host, port, info.IsDir())
	scpArgs = append(scpArgs, fmt.Sprintf("%s@%s:%s", user, hostname, remotePath), localPath)

	return fb.runSCPCommand(scpArgs)
}

func (fb *FileBrowser) getSSHParams() (host, user, hostname, port string) {
	host = fb.hostEntry.Text
	user = fb.userEntry.Text

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

	hostname = ssh_config.Get(host, "HostName")
	if hostname == "" {
		hostname = host
	}

	port = ssh_config.Get(host, "Port")
	if port == "" {
		port = "22"
	}

	return
}

func (fb *FileBrowser) buildSCPArgs(host, port string, isDir bool) []string {
	var args []string

	if isDir {
		args = append(args, "-r")
	}

	if port != "22" {
		args = append(args, "-P", port)
	}

	if fb.keyEntry.Text != "" {
		args = append(args, "-i", fb.keyEntry.Text)
	} else {
		identityFiles := ssh_config.GetAll(host, "IdentityFile")
		for _, keyPath := range identityFiles {
			if strings.HasPrefix(keyPath, "~/") {
				homeDir, _ := os.UserHomeDir()
				keyPath = filepath.Join(homeDir, keyPath[2:])
			}
			if _, err := os.Stat(keyPath); err == nil {
				args = append(args, "-i", keyPath)
				break
			}
		}
	}

	if proxyCommand := ssh_config.Get(host, "ProxyCommand"); proxyCommand != "" && proxyCommand != "none" {
		args = append(args, "-o", fmt.Sprintf("ProxyCommand=%s", proxyCommand))
	}

	args = append(args,
		"-o", "StrictHostKeyChecking=no",
		"-o", "UserKnownHostsFile=/dev/null",
	)

	return args
}

func (fb *FileBrowser) runSCPCommand(args []string) error {
	cmd := exec.Command("scp", args...)

	if fb.passEntry.Text != "" {
		cmd.Env = append(os.Environ(), "SSH_ASKPASS_REQUIRE=never")
	}

	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("scp failed: %v, output: %s", err, string(output))
	}
	return nil
}

func (fb *FileBrowser) buildRecursiveConfirmMessage(action string, dirs []string) string {
	var msg string
	if len(dirs) == 1 {
		msg = fmt.Sprintf("You have selected a directory:\n• %s\n\nThis will recursively %s all contents. Continue?", dirs[0], action)
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
		msg += fmt.Sprintf("\nThis will recursively %s all contents. Continue?", action)
	}
	return msg
}
