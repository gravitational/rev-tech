#!/bin/bash

# Load environment variables
if [ ! -f .env ]; then
    echo "Error: .env file not found."
    echo "Please copy .env.example to .env and set your Teleport cluster domain."
    echo ""
    echo "Run: cp .env.example .env"
    echo "Then edit .env to set TELEPORT_TRUST_DOMAIN"
    exit 1
fi

source .env

# Check if TELEPORT_TRUST_DOMAIN is set
if [ -z "$TELEPORT_TRUST_DOMAIN" ]; then
    echo "Error: TELEPORT_TRUST_DOMAIN is not set in .env file."
    echo "Please edit .env and set your Teleport cluster domain."
    echo ""
    echo "Example: TELEPORT_TRUST_DOMAIN=example.teleport.sh"
    exit 1
fi

echo "Configuring trust domain: $TELEPORT_TRUST_DOMAIN"
echo ""

# List of files to update
FILES=(
    "istio/istio-config.yaml"
    "tbot/tbot-config.yaml"
    "tbot/tbot-daemonset.yaml"
    "sockshop/sock-shop-policies.yaml"
)

# Check if any files still have the placeholder
NEEDS_UPDATE=false
for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        if grep -q "YOUR-CLUSTER.teleport.sh" "$file"; then
            NEEDS_UPDATE=true
            echo "✓ Will update: $file"
        else
            echo "⊘ Already configured: $file"
        fi
    else
        echo "⚠ File not found: $file"
    fi
done

if [ "$NEEDS_UPDATE" = false ]; then
    echo ""
    echo "All files are already configured with a trust domain."
    echo "If you want to change it, manually edit the files or reset them first."
    exit 0
fi

echo ""
read -p "Continue with configuration? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Configuration cancelled."
    exit 0
fi

# Update each file
echo ""
for file in "${FILES[@]}"; do
    if [ -f "$file" ] && grep -q "YOUR-CLUSTER.teleport.sh" "$file"; then
        # Use sed to replace the placeholder with the actual trust domain
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS sed requires -i with empty string
            sed -i '' "s/YOUR-CLUSTER\.teleport\.sh/$TELEPORT_TRUST_DOMAIN/g" "$file"
        else
            # Linux sed
            sed -i "s/YOUR-CLUSTER\.teleport\.sh/$TELEPORT_TRUST_DOMAIN/g" "$file"
        fi
        echo "✅ Updated: $file"
    fi
done

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "✓ Configuration complete!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Trust domain '$TELEPORT_TRUST_DOMAIN' has been configured in all files."
echo "You can now proceed with the Quick Start steps."
