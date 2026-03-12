package main

import (
	"io"
	"io/fs"
	"os/exec"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/widget"
	"github.com/pkg/sftp"
	"golang.org/x/crypto/ssh"
)

// RemoteFile represents a file on the remote server
type RemoteFile struct {
	Name    string
	Size    int64
	ModTime time.Time
	IsDir   bool
}

// SSHConnection holds the SSH client and SFTP client
type SSHConnection struct {
	client     *ssh.Client
	sftpClient *sftp.Client
	host       string
	connected  bool
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

// FileBrowser is the main application struct
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
	hostEntry           *widget.Entry
	userEntry           *widget.Entry
	passEntry           *widget.Entry
	keyEntry            *widget.Entry
	connectButton       *widget.Button
	terminalBtn         *widget.Button
	useConfigCheck      *widget.Check
	keyBrowseBtn        *widget.Button
	saveSettingsBtn     *widget.Button
	loadSettingsBtn     *widget.Button
	clearSettingsBtn    *widget.Button
	deleteSettingsBtn   *widget.Button
	savedSettingsSelect *widget.Select
	teleportHelpBtn     *widget.Button

	mainWindow fyne.Window
}

// proxyConn wraps stdin/stdout of a ProxyCommand process
type proxyConn struct {
	stdin  io.WriteCloser
	stdout io.ReadCloser
	stderr io.ReadCloser
	cmd    *exec.Cmd
}
