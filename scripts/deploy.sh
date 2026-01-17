#!/bin/bash
set -e

PACKAGE_DIR="${1:?Error: Package directory path not provided}"
RESTART_MODE="${2:-}"  # "-c" to restart only Connect, default restarts full cluster
KAFKA_CONNECT_PLUGINS_DIR="/usr/share/java/connect_plugins/"
PLUGIN_DIR="${KAFKA_CONNECT_PLUGINS_DIR}confluentinc-kafka-connect-jdbc"

# Validate package directory
if [ ! -d "$PACKAGE_DIR" ]; then
    echo "✗ ERROR: Package directory not found: $PACKAGE_DIR"
    exit 1
fi

# Handle nested directory structure (check for confluentinc-kafka-connect-jdbc subdirectory)
if [ -d "$PACKAGE_DIR/confluentinc-kafka-connect-jdbc" ]; then
    PACKAGE_DIR="$PACKAGE_DIR/confluentinc-kafka-connect-jdbc"
    echo "Found nested package structure, using: $PACKAGE_DIR"
fi

# Validate manifest exists
if [ ! -f "$PACKAGE_DIR/manifest.json" ]; then
    echo "✗ ERROR: manifest.json not found at $PACKAGE_DIR/manifest.json"
    exit 1
fi

echo "Deploying kafka-connect-jdbc from: $PACKAGE_DIR"
echo "Target plugin directory: $PLUGIN_DIR"
echo ""

# Remove existing plugin directory
echo "Removing existing plugin directory..."
sudo rm -rf "$PLUGIN_DIR" 2>/dev/null || true

# Create plugin directory
echo "Creating plugin directory..."
sudo mkdir -p "$PLUGIN_DIR"

# Copy entire package contents to plugin directory
echo "Copying package contents..."
sudo cp -r "$PACKAGE_DIR"/* "$PLUGIN_DIR/" || {
    echo "✗ ERROR: Failed to copy package contents"
    exit 1
}

# Set ownership recursively
echo "Setting ownership..."
sudo chown -R cp-kafka-connect:confluent "$PLUGIN_DIR"

# Set permissions (755 for dirs, 644 for files)
echo "Setting permissions..."
sudo find "$PLUGIN_DIR" -type d -exec chmod 755 {} \;
sudo find "$PLUGIN_DIR" -type f -exec chmod 644 {} \;

# Verify deployment
echo ""
echo "Verifying deployment..."
echo ""
echo "=== Plugin Directory Structure ==="
sudo find "$PLUGIN_DIR" -type f | head -20
echo ""
echo "=== Manifest.json ==="
if [ -f "$PLUGIN_DIR/manifest.json" ]; then
    echo "✓ Manifest exists"
    sudo head -5 "$PLUGIN_DIR/manifest.json"
else
    echo "⚠ Warning: manifest.json not found (may be in subdirectory)"
fi
echo ""
echo "=== Plugin Lib Directory ==="
if [ -d "$PLUGIN_DIR/lib" ]; then
    echo "✓ JARs directory exists"
    sudo ls -lah "$PLUGIN_DIR/lib/"
else
    echo "✗ WARNING: JARs directory not found at $PLUGIN_DIR/lib/"
fi
echo ""
echo "=== Permissions ==="
stat -c "Plugin dir: %A (%U:%G)" "$PLUGIN_DIR" 2>/dev/null || stat -f "Plugin dir: %Lp (%Su:%Sg)" "$PLUGIN_DIR"
echo ""

# Restart Kafka/Connect based on mode
echo "Restarting Kafka/Connect..."
if [ "$RESTART_MODE" = "-c" ]; then
    echo "Restart mode: Connect only"
    echo "Stopping Kafka Connect..."
    sudo /usr/local/bin/res_scripts/kafka_stop.sh -c
    if [ $? -ne 0 ]; then
        echo "✗ Failed to stop Kafka Connect"
        exit 1
    fi
    echo "✓ Kafka Connect stopped"
    
    echo "Starting Kafka Connect..."
    sudo /usr/local/bin/res_scripts/kafka_start.sh -c
    if [ $? -ne 0 ]; then
        echo "✗ Failed to start Kafka Connect"
        exit 1
    fi
    echo "✓ Kafka Connect started"
else
    echo "Restart mode: Full cluster"
    echo "Stopping Kafka..."
    sudo /usr/local/bin/res_scripts/kafka_stop.sh
    if [ $? -ne 0 ]; then
        echo "✗ Failed to stop Kafka"
        exit 1
    fi
    echo "✓ Kafka stopped"
    
    echo "Starting Kafka..."
    sudo /usr/local/bin/res_scripts/kafka_start.sh
    if [ $? -ne 0 ]; then
        echo "✗ Failed to start Kafka"
        exit 1
    fi
    echo "✓ Kafka started"
fi

echo "Checking status..."
sudo /usr/local/bin/res_scripts/kafka_status.sh

# Cleanup temporary files
echo ""
echo "Cleaning up temporary deployment files..."
rm -rf "$1" 2>/dev/null || true
rm -f /tmp/deploy.sh 2>/dev/null || true
echo "✓ Cleanup complete"

echo "✓ Deployment complete!"
