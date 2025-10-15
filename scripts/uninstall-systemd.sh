#!/bin/bash
###############################################################################
# GPS Data Capture Worker Service - Systemd Uninstallation Script
# 
# This script removes the GPS Data Capture systemd service
#
# Usage: sudo ./uninstall-systemd.sh [--keep-data]
###############################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration (must match install script)
SERVICE_NAME="gpsdatacapture"
APP_NAME="GpsDataCaptureWorkerService"
INSTALL_DIR="/opt/gpsdatacapture"
DATA_DIR="/var/gpsdatacapture"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
SERVICE_USER="gpsservice"
SERVICE_GROUP="gpsdata"

# Parse arguments
KEEP_DATA=false
if [ "$1" == "--keep-data" ]; then
    KEEP_DATA=true
fi

echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}  GPS Data Capture Worker Service - Uninstallation${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
    exit 1
fi

# Step 1: Stop the service
echo -e "${YELLOW}Step 1: Stopping service...${NC}"
if systemctl is-active --quiet ${SERVICE_NAME}; then
    systemctl stop ${SERVICE_NAME}
    echo -e "${GREEN}✓${NC} Service stopped"
else
    echo -e "${BLUE}ℹ${NC} Service is not running"
fi
echo ""

# Step 2: Disable the service
echo -e "${YELLOW}Step 2: Disabling service...${NC}"
if systemctl is-enabled --quiet ${SERVICE_NAME} 2>/dev/null; then
    systemctl disable ${SERVICE_NAME}
    echo -e "${GREEN}✓${NC} Service disabled"
else
    echo -e "${BLUE}ℹ${NC} Service is not enabled"
fi
echo ""

# Step 3: Remove service file
echo -e "${YELLOW}Step 3: Removing service file...${NC}"
if [ -f "${SERVICE_FILE}" ]; then
    rm -f ${SERVICE_FILE}
    echo -e "${GREEN}✓${NC} Removed ${SERVICE_FILE}"
else
    echo -e "${BLUE}ℹ${NC} Service file not found"
fi
systemctl daemon-reload
echo -e "${GREEN}✓${NC} Systemd daemon reloaded"
echo ""

# Step 4: Remove installation directory
echo -e "${YELLOW}Step 4: Removing installation directory...${NC}"
if [ -d "${INSTALL_DIR}" ]; then
    rm -rf ${INSTALL_DIR}
    echo -e "${GREEN}✓${NC} Removed ${INSTALL_DIR}"
else
    echo -e "${BLUE}ℹ${NC} Installation directory not found"
fi
echo ""

# Step 5: Handle data directory
echo -e "${YELLOW}Step 5: Handling data directory...${NC}"
if [ -d "${DATA_DIR}" ]; then
    if [ "$KEEP_DATA" = true ]; then
        echo -e "${BLUE}ℹ${NC} Data directory preserved: ${DATA_DIR}"
        echo -e "${YELLOW}  To manually remove data later:${NC}"
        echo "    sudo rm -rf ${DATA_DIR}"
    else
        # Ask for confirmation
        echo -e "${YELLOW}Warning: This will delete all GPS data in ${DATA_DIR}${NC}"
        read -p "Delete data directory? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf ${DATA_DIR}
            echo -e "${GREEN}✓${NC} Removed data directory: ${DATA_DIR}"
        else
            echo -e "${BLUE}ℹ${NC} Data directory preserved: ${DATA_DIR}"
        fi
    fi
else
    echo -e "${BLUE}ℹ${NC} Data directory not found"
fi
echo ""

# Step 6: Remove service user and group
echo -e "${YELLOW}Step 6: Removing service user and group...${NC}"
if id -u ${SERVICE_USER} > /dev/null 2>&1; then
    userdel ${SERVICE_USER}
    echo -e "${GREEN}✓${NC} Removed user: ${SERVICE_USER}"
else
    echo -e "${BLUE}ℹ${NC} User ${SERVICE_USER} not found"
fi

if getent group ${SERVICE_GROUP} > /dev/null; then
    groupdel ${SERVICE_GROUP}
    echo -e "${GREEN}✓${NC} Removed group: ${SERVICE_GROUP}"
else
    echo -e "${BLUE}ℹ${NC} Group ${SERVICE_GROUP} not found"
fi
echo ""

# Summary
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}  Uninstallation Complete!${NC}"
echo -e "${GREEN}================================================================${NC}"
echo ""
echo -e "${BLUE}Removed:${NC}"
echo "  - Systemd service"
echo "  - Installation directory: ${INSTALL_DIR}"
echo "  - Service user: ${SERVICE_USER}"
echo "  - Service group: ${SERVICE_GROUP}"

if [ "$KEEP_DATA" = true ] || [ -d "${DATA_DIR}" ]; then
    echo ""
    echo -e "${YELLOW}Data directory still exists:${NC}"
    echo "  ${DATA_DIR}"
    if [ -d "${DATA_DIR}" ]; then
        echo "  Files: $(find ${DATA_DIR} -type f | wc -l)"
        echo "  Size: $(du -sh ${DATA_DIR} 2>/dev/null | cut -f1)"
    fi
fi

echo ""
echo -e "${GREEN}GPS Data Capture service has been uninstalled.${NC}"

