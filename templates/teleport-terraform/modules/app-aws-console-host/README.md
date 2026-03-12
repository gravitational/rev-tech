# AWS Console App Host Module

Deploys a single EC2 instance running Teleport App Service (plus SSH service for troubleshooting) and configures static AWS Console apps directly in `teleport.yaml` (app B optional).

The module also attaches an IAM instance profile to the host so Teleport App Service can use EC2 instance metadata credentials for AWS role assumption.
