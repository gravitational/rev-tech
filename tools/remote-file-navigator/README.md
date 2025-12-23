# Remote Server File Navigator

A dual-pane file browser for managing local and remote files over SSH/SFTP with SCP transfer support.
It is compatible with Teleport with the `ssh_config` configuration.


<img width="1392" height="868" alt="image" src="https://github.com/user-attachments/assets/d7309a1a-3b3f-4002-be34-544db3979ed8" />


## Features

- **Dual-pane interface**: Local files on the left, remote files on the right
- **SSH config support**: Use your existing `~/.ssh/config` aliases
- **SCP file transfers**: Upload and download files/directories
- **Teleport integration**: Connect to Teleport-protected servers
- **Save connections**: Store frequently used connection settings
- **Terminal launch**: Open SSH terminal sessions directly

## Supported Environments

  This should fully run in Linux and MacOS environments. Windows
  could have some compatiblity issues and there are tools such
  as [WinSCP](https://goteleport.com/docs/connect-your-client/third-party/putty-winscp/) are probably better clients.

## Building

This was built and test with `go 1.25.5`

```bash
 go mod init remote-file-nav
 go mod tidy
 go build
```

Building in Ubuntu 24.04 docker example:

```bash
apt update && apt install curl wget git gcc -y
wget -c https://go.dev/dl/go1.25.0.linux-amd64.tar.gz
tar -C /usr/local/ -xzf go1.25.0.linux-amd64.tar.gz
cat >> .bashrc < EOF
export PATH=$PATH:/usr/local/go/bin
EOF
source .bashrc
apt install libx11-dev  libxrandr-dev \
    libxcursor-dev \
    libgl1-mesa-dev \
    libxinerama-dev \
    libxi-dev \
    pkg-config \
    xorg-dev -y
# adjust to include a branch if required
git clone https://github.com/gravitational/rev-tech 
cd rev-tech/tools/remote-file-navigator/
go mod init remote-file-nav
go mod tidy
CGO_ENABLED=1 GOARCH=arm64 go build
```

## Running:

```bash
./remote-file-nav
```


## Quick Start

### Connecting to a Remote Server

1. **Using SSH Config (Recommended)**
   - Ensure "Use SSH config" is checked
   - Enter your SSH host alias in the **Host** field (e.g., `myserver` or `se-ag-dev-east.a4232.teleportdemo.com`)
   - Click **Show Hosts** to see available hosts from your `~/.ssh/config`
   - Enter **User** and **Pass** (password/passphrase) if required
   - Click **Connect**

2. **Manual Connection**
   - Uncheck "Use SSH config"
   - Enter the full hostname in **Host**
   - Enter **User**, **Pass**, and optionally specify an SSH **Key** path
   - Click **Connect**

### Uploading Files (Local → Remote)

1. Connect to a remote server
2. Navigate to the desired **remote destination** directory using the right pane
3. In the **left pane** (Local Files), check the boxes next to files/folders you want to upload
4. Click **Upload ⬆** button (shows count of selected items)
5. For directories, confirm the recursive upload when prompted

### Downloading Files (Remote → Local)

1. Connect to a remote server
2. Navigate to the desired **local destination** directory using the left pane
3. In the **right pane** (Remote Files), check the boxes next to files/folders you want to download
4. Click **Download ⬇** button (shows count of selected items)
5. For directories, confirm the recursive download when prompted

### Navigation

| Action | How To |
|--------|--------|
| Go up one directory | Click **Up** button or **← Up** |
| Go to home directory | Click **Home** button or **🏠 Home** |
| Enter a directory | Click on the folder name |
| Go to specific path | Edit the **Path** field and press Enter or click **Go** |
| Sort files | Click **Name**, **Size**, or **Date** column headers |
| Show hidden files | Check **Show Hidden** |

### Managing Files

- **Delete local files**: Select files with checkboxes → Click **Delete**
- **Delete remote files**: Select files with checkboxes → Click **Delete**
- **Open terminal**: Click **Terminal** to launch an SSH session in your system terminal

### Saving Connections

1. Configure your connection settings (Host, User, Key, etc.)
2. Click **Save** and enter a name for the connection
3. Access saved connections from the dropdown menu
4. Use **Load**, **Clear**, or **Delete** to manage saved settings

> ⚠️ **Note**: Passwords are never saved for security reasons

### Connecting to Teleport-Protected Servers

Click the **Teleport Setup** button for detailed instructions, or follow these steps:

1. Run `tsh config` and add the output to `~/.ssh/config`
2. Run `tsh ls` to list available servers
3. Use the format `<nodename>.<cluster>` for the host (e.g., `myhost.example.teleport.sh`)
4. Ensure you're logged in with `tsh login --proxy=<your-proxy>`

## Interface Overview
```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Connection Bar: [Use SSH config] [Host] [Show Hosts] [Save/Load/Clear]      │
│                 [User] [Pass] [Key] [Connect] [Terminal] [Teleport Setup]   │
├────────────────────────────────┬────────────────────────────────────────────┤
│ LOCAL FILES                    │ REMOTE FILES                               │
│ [Up] [Home] [Path]             │ [Up] [Home] [Path]                    [Go] │
├────────────────────────────────┼────────────────────────────────────────────┤
│ ☐ 📁 folder1         <DIR>     │ ☐ 📁 folder1         <DIR>                 │
│ ☐ 📁 folder2         <DIR>     │ ☐ 📄 file.txt        6.5 KB                │
│ ☐ 📄 file.txt        1.5 KB    │                                            │
├────────────────────────────────┼────────────────────────────────────────────┤
│ [Upload ⬆] [Delete]            │ [Download ⬇] [Delete]                      │
│ Local: 25 directories, 55 files│ Remote: 0 directories, 3 files             │
└────────────────────────────────┴────────────────────────────────────────────┘
```

## Keyboard Shortcuts

- **Enter** in Host/User/Pass/Key fields: Initiate connection
- **Enter** in Path field: Navigate to entered path


## Dependencies

- [Fyne](https://fyne.io/) - Cross-platform GUI toolkit
- [golang.org/x/crypto/ssh](https://pkg.go.dev/golang.org/x/crypto/ssh) - SSH client
- [github.com/pkg/sftp](https://github.com/pkg/sftp) - SFTP client
- [github.com/kevinburke/ssh_config](https://github.com/kevinburke/ssh_config) - SSH config parser
