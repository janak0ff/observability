#!/bin/bash

# Script to switch between local and S3 storage for Loki

set -e

LOKI_CONFIG="../loki/loki-config.yaml"
ENV_FILE="../.env"
DOCKER_COMPOSE="../docker-compose.yml"

echo "Loki Storage Switcher"
echo "====================="
echo "Current configuration:"
echo "1) Local Storage (default)"
echo "2) S3 Storage"
echo ""
read -p "Select storage type (1 or 2): " choice

case $choice in
    1)
        echo "Switching to LOCAL storage..."
        
        # Update loki-config.yaml
        sed -i 's/# object_store: s3/object_store: filesystem/' $LOKI_CONFIG
        sed -i 's/object_store: s3/# object_store: s3/' $LOKI_CONFIG
        
        # Comment out S3 storage_config and uncomment filesystem
        # This is a simplified example - you might need more precise sed commands
        
        echo "✅ Switched to local storage"
        ;;
        
    2)
        echo "Switching to S3 storage..."
        echo "⚠️  Make sure you have configured AWS credentials in .env file"
        
        # Update loki-config.yaml
        sed -i 's/object_store: filesystem/# object_store: filesystem/' $LOKI_CONFIG
        sed -i 's/# object_store: s3/object_store: s3/' $LOKI_CONFIG
        
        # Uncomment S3 storage_config and comment out filesystem
        # This is a simplified example - you might need more precise sed commands
        
        echo "✅ Switched to S3 storage"
        echo "Next steps:"
        echo "1. Uncomment S3 environment variables in .env"
        echo "2. Uncomment S3 environment in docker-compose.yml"
        echo "3. Run: docker-compose restart loki"
        ;;
        
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac