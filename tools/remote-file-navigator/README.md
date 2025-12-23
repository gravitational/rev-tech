
Remote File Navigator is a file system tool allows for navigating and transfering
files to and from remote ssh servers.  It is compatible with Teleport with the 
`ssh_config` configuration.


to build:

This was built and test with `go 1.25.5`

```bash
 go mod init remote-file-nav
 go mod tidy
 go build
```

Running:

```bash
./remote-file-nav
```
