# All-up POC — every major capability in one deployment. ~$8-12/day.
profile_label = "full-platform"

enable_ssh         = true
enable_postgres    = true
enable_mongodb     = true
enable_rds_mysql   = true
enable_grafana     = true
enable_httpbin     = true
enable_demo_panel  = true
enable_aws_console = true
enable_windows     = true
# Teleport 19+ only — drop this flag on 18.x clusters.
enable_linux_desktop = true
enable_mcp           = true
