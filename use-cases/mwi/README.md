# MWI (Machine & Workload Identity)

## Key Concepts and Technologies

*   **Teleport's Ephemeral Certificates**: The repository demonstrates Teleport's ability to **issue ephemeral certificates using Machine and Workload Identity**. This approach provides short-lived credentials for access, greatly reducing the attack surface associated with long-lived static secrets.
*   **`tbot` for Local Database Tunnels**: A central aspect of this example is the use of `tbot`. Tbot enables secure connectivity to databases without directly exposing them or embedding sensitive credentials in CI/CD pipelines or local configurations.
*   **Simplified CI/CD Journey**: By utilizing Teleport's identity-based access and ephemeral certificates, the process of logging in and accessing resources within the CI/CD pipeline becomes more secure and less complex, **minimizing secrets** that need to be managed.

## Examples

- [Github](ci-cd/github/README.md)