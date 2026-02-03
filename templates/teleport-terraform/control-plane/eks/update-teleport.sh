#!/bin/bash
# Improved Teleport Demo Update Manager
# Optimized for frequent Teleport updates without risking EKS infrastructure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TFVARS_FILE="${SCRIPT_DIR}/2-teleport/terraform.tfvars"
BACKUP_DIR="${SCRIPT_DIR}/backups"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

KUBECTL_TIMEOUT=${KUBECTL_TIMEOUT:-300}
TERRAFORM_TIMEOUT=${TERRAFORM_TIMEOUT:-600}

log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# ==========================================
# UTILITY FUNCTIONS 
# ==========================================

validate_version() {
    local version="$1"
    # Support formats: 17.1.0, 17.1.0-dev, 17.1.0-rc.1
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$ ]]; then
        error "Invalid version format. Use format: 17.1.0 or 17.1.0-dev"
    fi
}

cleanup_old_backups() {
    local backup_count=$(ls -1 "${BACKUP_DIR}"/terraform.tfvars.* 2>/dev/null | wc -l)
    if [[ $backup_count -gt 10 ]]; then
        log "Cleaning up old backups (keeping last 10)..."
        ls -t "${BACKUP_DIR}"/terraform.tfvars.* | tail -n +11 | xargs rm -f
    fi
}

get_cluster_region() {
    if [[ -f "${SCRIPT_DIR}/1-cluster/terraform.tfstate" ]]; then
        cd "${SCRIPT_DIR}/1-cluster"
        terraform output -raw region 2>/dev/null || echo "us-east-2"
        cd "$SCRIPT_DIR"
    else
        echo "us-east-2"  # fallback
    fi
}

# Deploy full environment (both layers)
deploy_all() {
    log "🚀 Deploying full Teleport demo environment..."
    
    # 1. Deploy EKS infrastructure
    log "Deploying EKS cluster..."
    cd "${SCRIPT_DIR}/1-cluster"
    terraform init -upgrade
    terraform plan -out=eks-plan
    terraform apply eks-plan
    cd "$SCRIPT_DIR"
    
    # 2. Deploy Teleport (automatically reads EKS state via remote state)
    log "Deploying Teleport configuration..."
    cd "${SCRIPT_DIR}/2-teleport"
    terraform init -upgrade
    terraform plan -out=k8s-plan
    terraform apply k8s-plan
    cd "$SCRIPT_DIR"
    
    success "Full deployment completed!"
    show_status
    show_kubeconfig_info
}

# Update only Teleport (optimized for monthly updates)
update_teleport() {
    local new_version=${1:-""}
    
    if [[ -z "$new_version" ]]; then
        error "Usage: $0 update-teleport 17.1.0"
    fi
    
    validate_version "$new_version"
    
    log "🔄 Updating Teleport to v$new_version..."
    
    cd "${SCRIPT_DIR}/2-teleport"
    
    # Backup current configuration
    if [[ -f "$TFVARS_FILE" ]]; then
        local backup_file="${BACKUP_DIR}/terraform.tfvars.$(date +%Y%m%d-%H%M%S)"
        cp "$TFVARS_FILE" "$backup_file"
        log "Backed up current config to: $backup_file"
        cleanup_old_backups
    else
        error "terraform.tfvars not found in 2-teleport/"
    fi
    
    # Update version in terraform.tfvars
    if grep -q "teleport_version" "$TFVARS_FILE"; then
        sed -i.bak "s/teleport_version = \".*\"/teleport_version = \"$new_version\"/" "$TFVARS_FILE"
        rm -f "${TFVARS_FILE}.bak" # Remove sed backup file
    else
        echo "teleport_version = \"$new_version\"" >> "$TFVARS_FILE"
    fi
    
    log "Updated terraform.tfvars with version $new_version"
    
    # Plan the update
    log "Planning Teleport update..."
    terraform plan -out=update-plan
    
    # Apply update (EKS infrastructure remains untouched)
    log "Applying Teleport update..."
    terraform apply update-plan
    rm -f update-plan
    
    # Verify rollout
    log "Waiting for Teleport rollout to complete..."
    local cluster_name
    cluster_name=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "unknown")
    
    if [[ "$cluster_name" != "unknown" ]]; then
        # Update kubeconfig if needed
        local region
        region=$(get_cluster_region)
        aws eks update-kubeconfig --region "$region" --name "$cluster_name" >/dev/null 2>&1 || warn "Could not update kubeconfig automatically"
        
        # Wait for rollout
        kubectl rollout status deployment/teleport-cluster -n teleport-cluster --timeout=${KUBECTL_TIMEOUT}s || warn "Rollout status check failed"
        
        # Verify pods are running
        log "Checking pod status..."
        kubectl get pods -n teleport-cluster
    fi
    
    cd "$SCRIPT_DIR"
    success "Teleport updated to v$new_version!"
    show_detailed_status
}

# Rollback Teleport to previous version
rollback_teleport() {
    log "🔄 Rolling back Teleport..."
    
    cd "${SCRIPT_DIR}/2-teleport"
    
    # Find latest backup
    local backup_file
    backup_file=$(ls -t "${BACKUP_DIR}"/terraform.tfvars.* 2>/dev/null | head -1)
    if [[ -z "$backup_file" ]]; then
        error "No backup file found to rollback to"
    fi
    
    log "Rolling back to: $(basename "$backup_file")"
    cp "$backup_file" "$TFVARS_FILE"
    
    # Apply rollback
    log "Applying rollback..."
    terraform plan -out=rollback-plan
    terraform apply rollback-plan
    rm -f rollback-plan
    
    cd "$SCRIPT_DIR"
    success "Teleport rollback completed!"
    show_status
}

# Show current status
show_status() {
    log "📋 Current Status"
    echo
    
    # EKS cluster info
    if [[ -f "${SCRIPT_DIR}/1-cluster/terraform.tfstate" ]]; then
        cd "${SCRIPT_DIR}/1-cluster"
        local cluster_name cluster_version
        cluster_name=$(terraform output -raw cluster_name 2>/dev/null || echo "unknown")
        cluster_version=$(terraform output -raw cluster_version 2>/dev/null || echo "unknown")
        echo "  🎯 EKS Cluster: $cluster_name (v$cluster_version)"
        cd "$SCRIPT_DIR"
    else
        echo "  ❌ EKS cluster not deployed"
    fi
    
    # Teleport info
    if [[ -f "${SCRIPT_DIR}/2-teleport/terraform.tfstate" ]]; then
        cd "${SCRIPT_DIR}/2-teleport"
        local teleport_version teleport_url cluster_name
        teleport_version=$(terraform output -raw teleport_version 2>/dev/null || echo "unknown")
        teleport_url=$(terraform output -raw teleport_url 2>/dev/null || echo "unknown")
        cluster_name=$(terraform output -raw cluster_name 2>/dev/null || echo "unknown")
        
        echo "  🔐 Teleport: v$teleport_version"
        echo "  🌐 Demo URL: $teleport_url"
        echo "  📛 Cluster Name: $cluster_name"
        cd "$SCRIPT_DIR"
    else
        echo "  ❌ Teleport not deployed"
    fi
    
    echo
}

# Show detailed status
show_detailed_status() {
    log "📋 Current Status"
    echo
    
    # EKS cluster info
    if [[ -f "${SCRIPT_DIR}/1-cluster/terraform.tfstate" ]]; then
        cd "${SCRIPT_DIR}/1-cluster"
        local cluster_name cluster_version
        cluster_name=$(terraform output -raw cluster_name 2>/dev/null || echo "unknown")
        cluster_version=$(terraform output -raw cluster_version 2>/dev/null || echo "unknown")
        echo "  🎯 EKS Cluster: $cluster_name (v$cluster_version)"
        cd "$SCRIPT_DIR"
    else
        echo "  ❌ EKS cluster not deployed"
    fi
    
    # Teleport info
    if [[ -f "${SCRIPT_DIR}/2-teleport/terraform.tfstate" ]]; then
        cd "${SCRIPT_DIR}/2-teleport"
        local teleport_version teleport_url cluster_name
        teleport_version=$(terraform output -raw teleport_version 2>/dev/null || echo "unknown")
        teleport_url=$(terraform output -raw teleport_url 2>/dev/null || echo "unknown")
        cluster_name=$(terraform output -raw cluster_name 2>/dev/null || echo "unknown")
        
        echo "  🔐 Teleport: v$teleport_version"
        echo "  🌐 Demo URL: $teleport_url"
        echo "  📛 Cluster Name: $cluster_name"
        
        # Enhanced pod status
        local eks_cluster_name
        eks_cluster_name=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "")
        
        if [[ -n "$eks_cluster_name" ]]; then
            echo "  📊 Pod Status:"
            kubectl get pods -n teleport-cluster --no-headers 2>/dev/null | while read line; do
                local pod_name=$(echo "$line" | awk '{print $1}')
                local status=$(echo "$line" | awk '{print $3}')
                local ready=$(echo "$line" | awk '{print $2}')
                
                if [[ "$status" == "Running" && "$ready" =~ ^[1-9]/[1-9] ]]; then
                    echo "    ✅ $pod_name: $status ($ready)"
                else
                    echo "    ⚠️  $pod_name: $status ($ready)"
                fi
            done || echo "    ℹ️  No pods found or cluster not accessible"
        fi
        cd "$SCRIPT_DIR"
    else
        echo "  ❌ Teleport not deployed"
    fi
    
    echo
}

# Show kubeconfig information
show_kubeconfig_info() {
    if [[ -f "${SCRIPT_DIR}/1-cluster/terraform.tfstate" ]]; then
        cd "${SCRIPT_DIR}/1-cluster"
        local update_cmd
        update_cmd=$(terraform output -raw kubeconfig_update_command 2>/dev/null || echo "unknown")
        if [[ "$update_cmd" != "unknown" ]]; then
            echo
            log "📝 To manually update kubeconfig if needed:"
            echo "  $update_cmd"
            echo
        fi
        cd "$SCRIPT_DIR"
    fi
}

# Safe cleanup with proper CRD handling
cleanup_all() {
    log "🧹 Cleaning up entire environment..."
    
    read -p "⚠️  This will DESTROY the entire environment. Are you sure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Cleanup cancelled"
        return 0
    fi
    
    # Clean up Teleport first (handles CRDs and custom resources safely)
    if [[ -f "${SCRIPT_DIR}/2-teleport/terraform.tfstate" ]]; then
        log "Cleaning up Teleport resources..."
        cd "${SCRIPT_DIR}/2-teleport"
        
        # Get cluster info for kubectl commands
        local cluster_name
        cluster_name=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "")
        
        if [[ -n "$cluster_name" ]]; then
            # Update kubeconfig for cleanup
            aws eks update-kubeconfig --region "$(terraform output -raw region 2>/dev/null || echo us-east-2)" --name "$cluster_name" >/dev/null 2>&1 || true
            
            # Safe CRD cleanup
            log "Removing Teleport custom resources..."
            kubectl delete teleportusers,teleportroles,teleportloginrules,teleportsamlconnectors,teleportaccesslists --all -A --timeout=60s 2>/dev/null || true
            
            # Remove finalizers if resources are stuck
            log "Removing finalizers..."
            for crd in teleportusers teleportroles teleportloginrules teleportsamlconnectors teleportaccesslists; do
                kubectl get "$crd" -A -o name 2>/dev/null | while read -r resource; do
                    kubectl patch "$resource" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
                done
            done
        fi
        
        # Terraform destroy
        terraform destroy -auto-approve
        cd "$SCRIPT_DIR"
    fi
    
    # Clean up EKS infrastructure
    if [[ -f "${SCRIPT_DIR}/1-cluster/terraform.tfstate" ]]; then
        log "Cleaning up EKS cluster..."
        cd "${SCRIPT_DIR}/1-cluster"
        terraform destroy -auto-approve
        cd "$SCRIPT_DIR"
    fi
    
    success "Full cleanup completed!"
}

# Check for available Teleport versions
check_versions() {
    log "🔍 Checking latest Teleport versions..."
    
    if command -v curl >/dev/null 2>&1; then
        local releases
        # Try with jq first (filters pre-releases)
        if command -v jq >/dev/null 2>&1; then
            releases=$(curl -s "https://api.github.com/repos/gravitational/teleport/releases" | \
                      jq -r '.[] | select(.prerelease == false) | .tag_name' | \
                      sed 's/^v//' | head -5 2>/dev/null)
            echo "Recent stable Teleport versions:"
        else
            # Fallback to original method
            releases=$(curl -s "https://api.github.com/repos/gravitational/teleport/releases" | \
                      grep '"tag_name"' | head -10 | sed 's/.*"v\([^"]*\)".*/\1/' | \
                      grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | head -5)
            echo "Recent Teleport versions:"
        fi
        
        if [[ -n "$releases" ]]; then
            echo "$releases" | sed 's/^/  /'
        else
            warn "Could not fetch version information"
        fi
    else
        warn "curl not available - cannot check versions"
    fi
    echo
}

# Validate environment
validate_env() {
    log "🔍 Validating environment..."
    
    # Check required tools
    local missing_tools=()
    for tool in terraform aws kubectl; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing_tools[*]}"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS credentials not configured or invalid"
    fi
    
    success "Environment validation passed"
}

usage() {
    cat << EOF
🎯 Teleport Demo Update Manager - Optimized for Monthly Updates

DESCRIPTION:
  Manages Teleport demo deployments with separate EKS and Teleport layers.
  EKS infrastructure stays stable while Teleport can be updated frequently.

COMMANDS:
  $0 deploy                     Deploy full environment (EKS + Teleport)
  $0 update-teleport VERSION    Update only Teleport (leaves EKS untouched)
  $0 rollback                   Rollback Teleport to previous version
  $0 status                     Show current versions and URLs
  $0 detailed_status            Show detailed status including pod health
  $0 versions                   Check latest available Teleport versions
  $0 validate                   Validate environment and dependencies
  $0 cleanup                    Safely destroy everything

EXAMPLES:
  # Initial deployment
  $0 deploy

  # Monthly Teleport updates (fast, safe, 2-3 minutes)
  $0 update-teleport 17.1.0
  $0 update-teleport 17.2.1

  # Check what versions are available
  $0 versions

  # If update causes issues
  $0 rollback

  # Check current status
  $0 status

WORKFLOW BENEFITS:
  ✅ No manual coordination between workspaces
  ✅ EKS cluster stays stable (expensive, slow to recreate)
  ✅ Teleport updates are fast and safe (2-3 minutes)
  ✅ Can rollback Teleport without affecting infrastructure
  ✅ Perfect for monthly update cycles
  ✅ Automatic CRD management prevents deletion issues
  ✅ Remote state eliminates manual kubeconfig management

ARCHITECTURE:
  1-cluster/   - EKS infrastructure (stable, rarely changed)
  2-teleport/  - Teleport deployment (frequently updated)
  3-rbac/      - Roles, SSO, and demo apps

EOF
}

# Main command dispatch
case "${1:-}" in
    "deploy") validate_env && deploy_all ;;
    "update-teleport") validate_env && update_teleport "${2:-}" ;;
    "rollback") validate_env && rollback_teleport ;;
    "status") show_status ;;
    "detailed_status") show_detailed_status ;;
    "versions") check_versions ;;
    "validate") validate_env ;;
    "cleanup") validate_env && cleanup_all ;;
    *) usage ;;
esac
