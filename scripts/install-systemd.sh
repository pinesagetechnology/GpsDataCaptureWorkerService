#!/bin/bash
###############################################################################
# GPS Data Capture Worker Service - Systemd Installation Script
# 
# This script installs the GPS Data Capture service as a systemd service
# on Linux systems (including Raspberry Pi)
#
# Usage: sudo ./install-systemd.sh [architecture]
#   architecture: linux-arm64 (default for Raspberry Pi)
#                 linux-x64 (for x64 Linux)
###############################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SERVICE_NAME="gpsdatacapture"
APP_NAME="GpsDataCaptureWorkerService"
INSTALL_DIR="/opt/gpsdatacapture"
DATA_DIR="/var/gpsdatacapture"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
SERVICE_USER="gpsservice"
SERVICE_GROUP="gpsdata"

# Default architecture (can be overridden)
ARCH="${1:-linux-arm64}"

echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}  GPS Data Capture Worker Service - Systemd Installation${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
    exit 1
fi

# Detect project directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
CSPROJ_PATH="${PROJECT_DIR}/${APP_NAME}/${APP_NAME}.csproj"

echo -e "${YELLOW}Configuration:${NC}"
echo "  Project Directory: ${PROJECT_DIR}"
echo "  Architecture: ${ARCH}"
echo "  Install Directory: ${INSTALL_DIR}"
echo "  Data Directory: ${DATA_DIR}"
echo "  Service User: ${SERVICE_USER}"
echo "  Service Group: ${SERVICE_GROUP}"
echo ""

# Check if .NET is installed
if ! command -v dotnet &> /dev/null; then
    echo -e "${RED}Error: .NET SDK/Runtime is not installed${NC}"
    echo "Please install .NET 8.0 first:"
    echo "  wget https://dot.net/v1/dotnet-install.sh -O dotnet-install.sh"
    echo "  chmod +x dotnet-install.sh"
    echo "  sudo ./dotnet-install.sh --channel 8.0"
    exit 1
fi

# Check if project exists
if [ ! -f "${CSPROJ_PATH}" ]; then
    echo -e "${RED}Error: Project file not found at ${CSPROJ_PATH}${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} .NET SDK found: $(dotnet --version)"
echo ""

# Step 1: Create service user and group
echo -e "${YELLOW}Step 1: Creating service user and group...${NC}"
if ! getent group ${SERVICE_GROUP} > /dev/null; then
    groupadd ${SERVICE_GROUP}
    echo -e "${GREEN}✓${NC} Created group: ${SERVICE_GROUP}"
else
    echo -e "${BLUE}ℹ${NC} Group ${SERVICE_GROUP} already exists"
fi

if ! id -u ${SERVICE_USER} > /dev/null 2>&1; then
    useradd -r -s /bin/false -g ${SERVICE_GROUP} ${SERVICE_USER}
    echo -e "${GREEN}✓${NC} Created user: ${SERVICE_USER}"
else
    echo -e "${BLUE}ℹ${NC} User ${SERVICE_USER} already exists"
fi

# Add service user to dialout group for serial port access
usermod -a -G dialout ${SERVICE_USER}
echo -e "${GREEN}✓${NC} Added ${SERVICE_USER} to dialout group (serial port access)"
echo ""

# Step 2: Create and configure data directory
echo -e "${YELLOW}Step 2: Creating shared data directory...${NC}"
mkdir -p ${DATA_DIR}
chown ${SERVICE_USER}:${SERVICE_GROUP} ${DATA_DIR}
chmod 775 ${DATA_DIR}  # rwxrwxr-x - Owner and group can read/write/execute
echo -e "${GREEN}✓${NC} Created data directory: ${DATA_DIR}"
echo -e "${GREEN}✓${NC} Set permissions: 775 (rwxrwxr-x)"

# Set SGID bit so new files inherit the group
chmod g+s ${DATA_DIR}
echo -e "${GREEN}✓${NC} Set SGID bit - new files will inherit group ownership"
echo ""

# Step 3: Stop existing service if running
echo -e "${YELLOW}Step 3: Checking for existing service...${NC}"
if systemctl is-active --quiet ${SERVICE_NAME}; then
    echo "Stopping existing service..."
    systemctl stop ${SERVICE_NAME}
    echo -e "${GREEN}✓${NC} Service stopped"
fi
echo ""

# Step 4: Build and publish the application
echo -e "${YELLOW}Step 4: Building and publishing application...${NC}"
cd "${PROJECT_DIR}/${APP_NAME}"
echo "Running: dotnet publish -c Release -r ${ARCH} --self-contained -o ${INSTALL_DIR}"
dotnet publish -c Release -r ${ARCH} --self-contained -o ${INSTALL_DIR}

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Build failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Application published to ${INSTALL_DIR}"
echo ""

# Step 5: Configure Azure Storage (if needed)
echo -e "${YELLOW}Step 5: Azure Storage Configuration${NC}"
echo ""
echo "Do you want to configure Azure Storage for GPS data upload?"
echo "This allows the service to automatically upload GPS data to Azure Blob Storage."
echo ""
read -p "Configure Azure Storage? (y/N): " CONFIGURE_AZURE

AZURE_CONNECTION=""
AZURE_CONTAINER="gps-data"

if [[ "$CONFIGURE_AZURE" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${BLUE}Azure Storage Configuration:${NC}"
    echo ""
    
    # Prompt for connection string
    echo "Enter your Azure Storage connection string:"
    echo "(You can find this in Azure Portal > Storage Account > Access Keys)"
    read -p "Connection String: " AZURE_CONNECTION
    
    # Prompt for container name with default
    echo ""
    echo "Enter the container name for GPS data:"
    read -p "Container Name [gps-data]: " AZURE_CONTAINER_INPUT
    
    # Use default if empty
    if [ -n "$AZURE_CONTAINER_INPUT" ]; then
        AZURE_CONTAINER="$AZURE_CONTAINER_INPUT"
    fi
    
    echo ""
    echo -e "${GREEN}✓${NC} Azure Storage will be configured with container: ${AZURE_CONTAINER}"
else
    echo -e "${BLUE}ℹ${NC} Skipping Azure Storage configuration"
fi
echo ""

# Step 6: Update appsettings.json with shared data directory and Azure Storage
echo -e "${YELLOW}Step 6: Configuring application settings...${NC}"
APPSETTINGS_FILE="${INSTALL_DIR}/appsettings.json"

if [ -f "${APPSETTINGS_FILE}" ]; then
    # Backup original
    cp "${APPSETTINGS_FILE}" "${APPSETTINGS_FILE}.bak"
    
    # Update DataDirectory using sed
    sed -i "s|\"DataDirectory\": \"[^\"]*\"|\"DataDirectory\": \"${DATA_DIR}\"|g" "${APPSETTINGS_FILE}"
    echo -e "${GREEN}✓${NC} Updated DataDirectory to: ${DATA_DIR}"
    
    # Update Azure Storage settings if configured
    if [ -n "$AZURE_CONNECTION" ]; then
        sed -i "s|\"AzureStorageConnectionString\": \"[^\"]*\"|\"AzureStorageConnectionString\": \"${AZURE_CONNECTION}\"|g" "${APPSETTINGS_FILE}"
        sed -i "s|\"AzureStorageContainerName\": \"[^\"]*\"|\"AzureStorageContainerName\": \"${AZURE_CONTAINER}\"|g" "${APPSETTINGS_FILE}"
        echo -e "${GREEN}✓${NC} Updated Azure Storage connection string"
        echo -e "${GREEN}✓${NC} Updated Azure Storage container name to: ${AZURE_CONTAINER}"
    fi
    
    echo -e "${BLUE}ℹ${NC} Backup saved: ${APPSETTINGS_FILE}.bak"
else
    echo -e "${RED}Warning: appsettings.json not found${NC}"
fi
echo ""

# Step 7: Set ownership and permissions on install directory
echo -e "${YELLOW}Step 7: Setting permissions...${NC}"
chown -R ${SERVICE_USER}:${SERVICE_GROUP} ${INSTALL_DIR}
chmod +x ${INSTALL_DIR}/${APP_NAME}
echo -e "${GREEN}✓${NC} Set ownership and executable permissions"
echo ""

# Step 8: Create systemd service file
echo -e "${YELLOW}Step 8: Creating systemd service file...${NC}"
cat > ${SERVICE_FILE} << EOF
[Unit]
Description=GPS Data Capture Worker Service
After=network.target
Documentation=https://github.com/yourrepo/gpsdatacapture

[Service]
Type=notify
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/${APP_NAME}
Restart=always
RestartSec=10
User=${SERVICE_USER}
Group=${SERVICE_GROUP}

# Environment
Environment=DOTNET_ENVIRONMENT=Production
Environment=ASPNETCORE_ENVIRONMENT=Production

# Hardening options
NoNewPrivileges=true
PrivateTmp=true

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

# Resource limits
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

echo -e "${GREEN}✓${NC} Created service file: ${SERVICE_FILE}"
echo ""

# Step 9: Reload systemd and enable service
echo -e "${YELLOW}Step 9: Enabling systemd service...${NC}"
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}
echo -e "${GREEN}✓${NC} Service enabled"
echo ""

# Step 10: Start the service
echo -e "${YELLOW}Step 10: Starting service...${NC}"
systemctl start ${SERVICE_NAME}
sleep 2

if systemctl is-active --quiet ${SERVICE_NAME}; then
    echo -e "${GREEN}✓${NC} Service started successfully"
else
    echo -e "${RED}✗${NC} Service failed to start"
    echo "Check logs with: sudo journalctl -u ${SERVICE_NAME} -f"
    exit 1
fi
echo ""

# Step 11: Show status
echo -e "${YELLOW}Step 11: Service Status${NC}"
systemctl status ${SERVICE_NAME} --no-pager -l
echo ""

# Summary and instructions
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}  Installation Complete!${NC}"
echo -e "${GREEN}================================================================${NC}"
echo ""
echo -e "${BLUE}Service Information:${NC}"
echo "  Service Name: ${SERVICE_NAME}"
echo "  Install Location: ${INSTALL_DIR}"
echo "  Data Directory: ${DATA_DIR}"
echo "  Service User: ${SERVICE_USER}:${SERVICE_GROUP}"
echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo "  Check status:    sudo systemctl status ${SERVICE_NAME}"
echo "  View logs:       sudo journalctl -u ${SERVICE_NAME} -f"
echo "  Stop service:    sudo systemctl stop ${SERVICE_NAME}"
echo "  Start service:   sudo systemctl start ${SERVICE_NAME}"
echo "  Restart service: sudo systemctl restart ${SERVICE_NAME}"
echo "  Disable service: sudo systemctl disable ${SERVICE_NAME}"
echo ""
echo -e "${BLUE}Data Access:${NC}"
echo "  Data files are saved in: ${DATA_DIR}"
echo "  All users in '${SERVICE_GROUP}' group can read/write/delete files"
echo ""
echo -e "${YELLOW}To allow a user to access GPS data:${NC}"
echo "  sudo usermod -a -G ${SERVICE_GROUP} <username>"
echo "  (User must log out and back in for group change to take effect)"
echo ""
echo -e "${YELLOW}To view GPS data files:${NC}"
echo "  ls -lh ${DATA_DIR}"
echo ""
echo -e "${GREEN}Installation complete! Service is running.${NC}"

