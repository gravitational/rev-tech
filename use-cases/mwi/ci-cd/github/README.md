# Github

## MWI
- [Database Tunnel Workflow](mwi-database-tunnel.yaml): An example demonstrating the use of Teleport for secure database tunneling, streamlining CI/CD workflows, and enhancing secret management
    - Prequisites
        The proper role to create resources within your Teleport Cluster: (`access`, `editor` )

    - Getting Started

        Download each of the files below and create the resources using `tctl create -f FILE-NAME-HERE.yaml`    

        - [Database Tunnel Bot](/templates/teleport/bots/database-tunnel-bot.yaml) - bot has scoped permissions to start a database tunnel
        - [Database Tunnel Role](/templates/teleport/roles/database-tunnel-role.yaml) - defines access to Teleport Protected Databaseses
        - [Database Tunnel Bot Token](/templates/teleport/tokens/database-tunnel-bot-token.yaml) - CI/CD pipeline token

    - Create a workflow in Github using the [following](mwi-database-tunnel.yaml) as reference

    - Reference
        - [Teleport Github actions](https://goteleport.com/docs/machine-workload-identity/machine-id/deployment/github-actions/)