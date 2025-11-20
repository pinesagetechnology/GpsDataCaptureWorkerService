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
# First, try to find dotnet in common locations
DOTNET_PATH=""
if command -v dotnet &> /dev/null; then
    DOTNET_PATH="dotnet"
elif [ -f "/root/.dotnet/dotnet" ]; then
    DOTNET_PATH="/root/.dotnet/dotnet"
    export PATH="/root/.dotnet:$PATH"
elif [ -f "$HOME/.dotnet/dotnet" ]; then
    DOTNET_PATH="$HOME/.dotnet/dotnet"
    export PATH="$HOME/.dotnet:$PATH"
elif [ -f "/usr/local/share/dotnet/dotnet" ]; then
    DOTNET_PATH="/usr/local/share/dotnet/dotnet"
    export PATH="/usr/local/share/dotnet:$PATH"
fi

if [ -z "$DOTNET_PATH" ] || ! "$DOTNET_PATH" --version &> /dev/null; then
    echo -e "${RED}Error: .NET SDK/Runtime is not installed or not found in PATH${NC}"
    echo ""
    echo "Please install .NET 9.0 first:"
    echo "  wget https://dot.net/v1/dotnet-install.sh -O dotnet-install.sh"
    echo "  chmod +x dotnet-install.sh"
    echo "  sudo ./dotnet-install.sh --channel 9.0"
    echo ""
    echo "After installation, you may need to add .NET to PATH:"
    echo "  export PATH=\$PATH:/root/.dotnet"
    echo "  # Or add to ~/.bashrc for permanent:"
    echo "  echo 'export PATH=\$PATH:/root/.dotnet' >> ~/.bashrc"
    exit 1
fi

# Check if project exists
if [ ! -f "${CSPROJ_PATH}" ]; then
    echo -e "${RED}Error: Project file not found at ${CSPROJ_PATH}${NC}"
    exit 1
fi

DOTNET_VERSION=$("$DOTNET_PATH" --version)
echo -e "${GREEN}✓${NC} .NET SDK found: ${DOTNET_VERSION} (at ${DOTNET_PATH})"
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
echo "Running: ${DOTNET_PATH} publish -c Release -r ${ARCH} --self-contained -o ${INSTALL_DIR}"
"${DOTNET_PATH}" publish -c Release -r ${ARCH} --self-contained -o ${INSTALL_DIR}

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Build failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Application published to ${INSTALL_DIR}"
echo ""

# Step 5: Configure API Endpoint (if needed)
echo -e "${YELLOW}Step 5: API Endpoint Configuration${NC}"
echo ""
echo "Do you want to configure an API endpoint to send GPS data?"
echo "This allows the service to automatically send GPS data to your API."
echo ""
read -p "Configure API Endpoint? (y/N): " CONFIGURE_API

API_ENDPOINT=""
API_KEY=""

if [[ "$CONFIGURE_API" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${BLUE}API Configuration:${NC}"
    echo ""
    
    # Prompt for API endpoint
    echo "Enter your API endpoint URL:"
    echo "(Example: https://api.example.com/gps/data)"
    read -p "API Endpoint: " API_ENDPOINT
    
    # Prompt for API key (optional)
    echo ""
    echo "Enter your API key (leave empty if not required):"
    read -p "API Key: " API_KEY
    
    echo ""
    echo -e "${GREEN}✓${NC} API will be configured with endpoint: ${API_ENDPOINT}"
else
    echo -e "${BLUE}ℹ${NC} Skipping API configuration"
fi
echo ""

# Step 6: Configure Azure Storage (if needed)
echo -e "${YELLOW}Step 6: Azure Storage Configuration${NC}"
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
    echo "(Format: DefaultEndpointsProtocol=https;AccountName=...;AccountKey=...;EndpointSuffix=core.windows.net)"
    echo ""
    read -p "Azure Storage Connection String: " AZURE_CONNECTION
    
    # Validate connection string is not empty
    if [ -z "$AZURE_CONNECTION" ]; then
        echo -e "${YELLOW}⚠${NC} Azure Storage connection string is empty. Skipping Azure Storage configuration."
        AZURE_CONNECTION=""
    else
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
    fi
else
    echo -e "${BLUE}ℹ${NC} Skipping Azure Storage configuration"
fi
echo ""

# Step 6b: Configure PostgreSQL (if needed)
echo -e "${YELLOW}Step 6b: PostgreSQL Configuration${NC}"
echo ""
echo "Do you want to configure PostgreSQL for GPS data storage?"
echo "This allows the service to automatically save GPS data to PostgreSQL database."
echo ""
read -p "Configure PostgreSQL? (y/N): " CONFIGURE_POSTGRES

POSTGRES_CONNECTION=""
POSTGRES_STORE_RAW_DATA="false"

if [[ "$CONFIGURE_POSTGRES" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${BLUE}PostgreSQL Configuration:${NC}"
    echo ""
    
    # Prompt for connection string
    echo "Enter your PostgreSQL connection string:"
    echo "(Format: Host=localhost;Port=5432;Database=iot_gateway;Username=user;Password=pass;Pooling=true;Minimum Pool Size=1;Maximum Pool Size=10;)"
    echo ""
    read -p "PostgreSQL Connection String: " POSTGRES_CONNECTION
    
    # Validate connection string is not empty
    if [ -z "$POSTGRES_CONNECTION" ]; then
        echo -e "${YELLOW}⚠${NC} PostgreSQL connection string is empty. Skipping PostgreSQL configuration."
        POSTGRES_CONNECTION=""
    else
        # Prompt for raw data storage
        echo ""
        echo "Do you want to store raw GPS data as JSON in the database?"
        echo "(This stores the complete GPS data as JSON in the raw_data column)"
        read -p "Store Raw Data? (y/N) [N]: " STORE_RAW_INPUT
        
        if [[ "$STORE_RAW_INPUT" =~ ^[Yy]$ ]]; then
            POSTGRES_STORE_RAW_DATA="true"
        fi
        
        echo ""
        echo -e "${GREEN}✓${NC} PostgreSQL will be configured"
        if [ "$POSTGRES_STORE_RAW_DATA" = "true" ]; then
            echo -e "${GREEN}✓${NC} Raw data storage enabled"
        fi
    fi
else
    echo -e "${BLUE}ℹ${NC} Skipping PostgreSQL configuration"
fi
echo ""

# Step 7: Update appsettings.json with shared data directory, API, and Azure Storage
echo -e "${YELLOW}Step 7: Configuring application settings...${NC}"
APPSETTINGS_FILE="${INSTALL_DIR}/appsettings.json"

if [ -f "${APPSETTINGS_FILE}" ]; then
    # Backup original
    cp "${APPSETTINGS_FILE}" "${APPSETTINGS_FILE}.bak"
    
    # Update DataDirectory using sed
    sed -i "s|\"DataDirectory\": \"[^\"]*\"|\"DataDirectory\": \"${DATA_DIR}\"|g" "${APPSETTINGS_FILE}"
    echo -e "${GREEN}✓${NC} Updated DataDirectory to: ${DATA_DIR}"
    
    # Update API settings if configured
    if [ -n "$API_ENDPOINT" ]; then
        sed -i "s|\"ApiEndpoint\": \"[^\"]*\"|\"ApiEndpoint\": \"${API_ENDPOINT}\"|g" "${APPSETTINGS_FILE}"
        echo -e "${GREEN}✓${NC} Updated API endpoint to: ${API_ENDPOINT}"
        
        if [ -n "$API_KEY" ]; then
            sed -i "s|\"ApiKey\": \"[^\"]*\"|\"ApiKey\": \"${API_KEY}\"|g" "${APPSETTINGS_FILE}"
            echo -e "${GREEN}✓${NC} Updated API key"
        fi
    fi
    
    # Update Azure Storage settings if configured
    if [ -n "$AZURE_CONNECTION" ]; then
        # Escape special characters in connection string for sed
        AZURE_CONNECTION_ESCAPED=$(printf '%s\n' "$AZURE_CONNECTION" | sed 's/[[\.*^$()+?{|]/\\&/g')
        sed -i "s|\"AzureStorageConnectionString\": \"[^\"]*\"|\"AzureStorageConnectionString\": \"${AZURE_CONNECTION_ESCAPED}\"|g" "${APPSETTINGS_FILE}"
        sed -i "s|\"AzureStorageContainerName\": \"[^\"]*\"|\"AzureStorageContainerName\": \"${AZURE_CONTAINER}\"|g" "${APPSETTINGS_FILE}"
        echo -e "${GREEN}✓${NC} Updated Azure Storage connection string"
        echo -e "${GREEN}✓${NC} Updated Azure Storage container name to: ${AZURE_CONTAINER}"
    fi
    
    # Update PostgreSQL settings if configured
    if [ -n "$POSTGRES_CONNECTION" ]; then
        # Escape special characters in connection string for sed
        POSTGRES_CONNECTION_ESCAPED=$(printf '%s\n' "$POSTGRES_CONNECTION" | sed 's/[[\.*^$()+?{|]/\\&/g')
        sed -i "s|\"PostgresConnectionString\": \"[^\"]*\"|\"PostgresConnectionString\": \"${POSTGRES_CONNECTION_ESCAPED}\"|g" "${APPSETTINGS_FILE}"
        sed -i "s|\"PostgresStoreRawData\": [a-z]*|\"PostgresStoreRawData\": ${POSTGRES_STORE_RAW_DATA}|g" "${APPSETTINGS_FILE}"
        echo -e "${GREEN}✓${NC} Updated PostgreSQL connection string"
        echo -e "${GREEN}✓${NC} Updated PostgreSQL raw data storage: ${POSTGRES_STORE_RAW_DATA}"
    fi
    
    # Determine the operating mode based on configuration
    MODE=""
    if [ -n "$API_ENDPOINT" ] && [ -n "$AZURE_CONNECTION" ] && [ -n "$POSTGRES_CONNECTION" ]; then
        MODE="ApiAzureAndPostgres"
    elif [ -n "$API_ENDPOINT" ] && [ -n "$AZURE_CONNECTION" ]; then
        MODE="ApiAndAzure"
    elif [ -n "$API_ENDPOINT" ] && [ -n "$POSTGRES_CONNECTION" ]; then
        MODE="ApiAndPostgres"
    elif [ -n "$AZURE_CONNECTION" ] && [ -n "$POSTGRES_CONNECTION" ]; then
        MODE="AzureAndPostgres"
    elif [ -n "$API_ENDPOINT" ]; then
        MODE="SendToApi"
    elif [ -n "$AZURE_CONNECTION" ]; then
        MODE="SendToAzureStorage"
    elif [ -n "$POSTGRES_CONNECTION" ]; then
        MODE="SaveToPostgres"
    else
        MODE="SaveToFile"
    fi
    
    sed -i "s|\"Mode\": \"[^\"]*\"|\"Mode\": \"${MODE}\"|g" "${APPSETTINGS_FILE}"
    echo -e "${GREEN}✓${NC} Mode set to: ${MODE}"
    
    # Ensure MinimumMovementDistanceMeters is set (default: 10.0)
    if ! grep -q "\"MinimumMovementDistanceMeters\"" "${APPSETTINGS_FILE}"; then
        # Add it before the closing brace of GpsSettings section
        # Find the last property before the closing brace and add after it
        sed -i '/"BatchSize"/a\    "MinimumMovementDistanceMeters": 10.0' "${APPSETTINGS_FILE}"
    fi
    echo -e "${GREEN}✓${NC} Minimum Movement Distance configured (default: 10.0 meters)"
    
    echo -e "${BLUE}ℹ${NC} Backup saved: ${APPSETTINGS_FILE}.bak"
else
    echo -e "${RED}Warning: appsettings.json not found${NC}"
fi
echo ""

# Step 8: Set ownership and permissions on install directory
echo -e "${YELLOW}Step 8: Setting permissions...${NC}"
chown -R ${SERVICE_USER}:${SERVICE_GROUP} ${INSTALL_DIR}
chmod +x ${INSTALL_DIR}/${APP_NAME}
echo -e "${GREEN}✓${NC} Set ownership and executable permissions"
echo ""

# Step 9: Create systemd service file
echo -e "${YELLOW}Step 9: Creating systemd service file...${NC}"
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

# Step 10: Reload systemd and enable service
echo -e "${YELLOW}Step 10: Enabling systemd service...${NC}"
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}
echo -e "${GREEN}✓${NC} Service enabled"
echo ""

# Step 11: Start the service
echo -e "${YELLOW}Step 11: Starting service...${NC}"
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

# Step 12: Show status
echo -e "${YELLOW}Step 12: Service Status${NC}"
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

if [ -n "$API_ENDPOINT" ]; then
    echo -e "${GREEN}API is configured!${NC}"
    echo "GPS data will be sent to: ${API_ENDPOINT}"
    echo ""
fi

if [ -n "$AZURE_CONNECTION" ]; then
    echo -e "${GREEN}Azure Storage is configured!${NC}"
    echo "GPS data will be uploaded to Azure Blob Storage container: ${AZURE_CONTAINER}"
    echo ""
fi

echo -e "${GREEN}Installation complete! Service is running.${NC}"

