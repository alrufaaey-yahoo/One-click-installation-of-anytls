#!/bin/bash

# anytls installation/uninstallation management script
# Features: Install anytls or completely uninstall (including systemd service cleanup)
# Supported architectures: amd64 (x86_64), arm64 (aarch64), armv7 (armv7l)

# Check root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Must be run as root or with sudo!"
    exit 1
fi

# Install necessary tools: wget, curl, unzip
function install_dependencies() {
    echo "[Initialization] Installing required dependencies (wget, curl, unzip)..."
    apt update -y >/dev/null 2>&1

    for dep in wget curl unzip; do
        if ! command -v $dep &>/dev/null; then
            echo "Installing $dep..."
            apt install -y $dep || {
                echo "Failed to install dependency: $dep, please manually run 'sudo apt install $dep' and try again."
                exit 1
            }
        fi
    done
}

# Call dependency installation function
install_dependencies

# Automatically detect system architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64)  BINARY_ARCH="amd64" ;;
    aarch64) BINARY_ARCH="arm64" ;;
    armv7l)  BINARY_ARCH="armv7" ;;
    *)       echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Configuration parameters (note: removed extra space after linux_)
DOWNLOAD_URL="https://github.com/anytls/anytls-go/releases/download/v0.0.8/anytls_0.0.8_linux_${BINARY_ARCH}.zip"
ZIP_FILE="/tmp/anytls_0.0.8_linux_${BINARY_ARCH}.zip"
BINARY_DIR="/usr/local/bin"
BINARY_NAME="anytls-server"
SERVICE_NAME="anytls"

# Improved IP retrieval function
get_ip() {
    local ip=""
    ip=$(ip -o -4 addr show scope global | awk '{print $4}' | cut -d'/' -f1 | head -n1)
    [ -z "$ip" ] && ip=$(ifconfig 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -n1)
    [ -z "$ip" ] && ip=$(curl -4 -s --connect-timeout 3 ifconfig.me 2>/dev/null || curl -4 -s --connect-timeout 3 icanhazip.com 2>/dev/null)
    
    if [ -z "$ip" ]; then
        echo "Failed to automatically retrieve IP, please manually enter the server IP address"
        read -p "Enter server IP address: " ip
    fi
    
    echo "$ip"
}

# Display menu
function show_menu() {
    clear
    echo "-------------------------------------"
    echo " anytls Service Management Script (${BINARY_ARCH} architecture) "
    echo "-------------------------------------"
    echo "1. Install anytls"
    echo "2. Uninstall anytls"
    echo "0. Exit"
    echo "-------------------------------------"
    read -p "Enter option [0-2]: " choice
    case $choice in
        1) install_anytls ;;
        2) uninstall_anytls ;;
        0) exit 0 ;;
        *) echo "Invalid option!" && sleep 1 && show_menu ;;
    esac
}

# Installation function
function install_anytls() {
    # Download
    echo "[1/6] Downloading anytls (${BINARY_ARCH} architecture)..."
    wget "$DOWNLOAD_URL" -O "$ZIP_FILE" || {
        echo "Download failed! Possible reasons:"
        echo "1. Network connection issue"
        echo "2. Binary for this architecture doesn't exist"
        exit 1
    }

    # Extract
    echo "[2/6] Extracting files..."
    unzip -o "$ZIP_FILE" -d "$BINARY_DIR" || {
        echo "Extraction failed! File may be corrupted"
        exit 1
    }
    chmod +x "$BINARY_DIR/$BINARY_NAME"

    # Input password
    read -p "Set anytls password: " PASSWORD
    [ -z "$PASSWORD" ] && {
        echo "Error: Password cannot be empty!"
        exit 1
    }

    # Input port (new feature)
    read -p "Enter listening port [default 8443]: " PORT
    [ -z "$PORT" ] && PORT=8443
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        echo "Invalid port number! Using default 8443"
        PORT=8443
    fi

    # Configure service
    echo "[3/6] Configuring systemd service..."
    cat > /etc/systemd/system/$SERVICE_NAME.service <<EOF
[Unit]
Description=anytls Service
After=network.target

[Service]
ExecStart=$BINARY_DIR/$BINARY_NAME -l 0.0.0.0:$PORT -p $PASSWORD
Restart=always
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

    # Start service
    echo "[4/6] Starting service..."
    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    systemctl start $SERVICE_NAME

    # Cleanup
    rm -f "$ZIP_FILE"

    # Get server IP
    SERVER_IP=$(get_ip)

    # Verification
    echo -e "\n\033[32m√ Installation complete!\033[0m"
    echo -e "\033[32m√ Architecture: ${BINARY_ARCH}\033[0m"
    echo -e "\033[32m√ Service name: $SERVICE_NAME\033[0m"
    echo -e "\033[32m√ Listening port: 0.0.0.0:${PORT}\033[0m"
    echo -e "\033[32m√ Password set to: $PASSWORD\033[0m"
    echo -e "\n\033[33mManagement commands:\033[0m"
    echo -e "  Start: systemctl start $SERVICE_NAME"
    echo -e "  Stop: systemctl stop $SERVICE_NAME"
    echo -e "  Restart: systemctl restart $SERVICE_NAME"
    echo -e "  Status: systemctl status $SERVICE_NAME"
    
    # Highlight connection information
    echo -e "\n\033[36m\033[1m〓 NekoBox Connection Information 〓\033[0m"
    echo -e "\033[30;43m\033[1m anytls://$PASSWORD@$SERVER_IP:$PORT/?insecure=1 \033[0m"
    echo -e "\033[33m\033[1mPlease securely store this connection information!\033[0m"
}

# Uninstallation function
function uninstall_anytls() {
    echo "Uninstalling anytls..."
    
    # Stop service
    if systemctl is-active --quiet $SERVICE_NAME; then
        systemctl stop $SERVICE_NAME
        echo "[1/4] Service stopped"
    fi

    # Disable service
    if systemctl is-enabled --quiet $SERVICE_NAME; then
        systemctl disable $SERVICE_NAME
        echo "[2/4] Autostart disabled"
    fi

    # Delete files
    if [ -f "$BINARY_DIR/$BINARY_NAME" ]; then
        rm -f "$BINARY_DIR/$BINARY_NAME"
        echo "[3/4] Binary file deleted"
    fi

    # Cleanup configuration
    if [ -f "/etc/systemd/system/$SERVICE_NAME.service" ]; then
        rm -f "/etc/systemd/system/$SERVICE_NAME.service"
        systemctl daemon-reload
        echo "[4/4] Service configuration removed"
    fi

    echo -e "\n\033[32m[Result]\033[0m anytls completely uninstalled!"
}

# Start menu
show_menu
