#!/bin/bash

cat << "EOF"
╔═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗

$$\      $$\  $$$$$$\           $$$$$$\              $$\                      $$$$$$\  $$\ $$\                       $$\     
$$ | $\  $$ |$$  __$$\         $$  __$$\             $$ |                    $$  __$$\ $$ |\__|                      $$ |    
$$ |$$$\ $$ |$$ /  \__|        $$ /  $$ |$$\   $$\ $$$$$$\    $$$$$$\        $$ /  \__|$$ |$$\  $$$$$$\  $$$$$$$\  $$$$$$\   
$$ $$ $$\$$ |$$ |$$$$\ $$$$$$\ $$$$$$$$ |$$ |  $$ |\_$$  _|  $$  __$$\       $$ |      $$ |$$ |$$  __$$\ $$  __$$\ \_$$  _|  
$$$$  _$$$$ |$$ |\_$$ |\______|$$  __$$ |$$ |  $$ |  $$ |    $$ /  $$ |      $$ |      $$ |$$ |$$$$$$$$ |$$ |  $$ |  $$ |    
$$$  / \$$$ |$$ |  $$ |        $$ |  $$ |$$ |  $$ |  $$ |$$\ $$ |  $$ |      $$ |  $$\ $$ |$$ |$$   ____|$$ |  $$ |  $$ |$$\ 
$$  /   \$$ |\$$$$$$  |        $$ |  $$ |\$$$$$$  |  \$$$$  |\$$$$$$  |      \$$$$$$  |$$ |$$ |\$$$$$$$\ $$ |  $$ |  \$$$$  |
\__/     \__| \______/         \__|  \__| \______/    \____/  \______/        \______/ \__|\__| \_______|\__|  \__|   \____/ 
                                                                       
                                                                       
   by: brennocm (https://github.com/brennocm/wg-auto)
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝  
EOF

# Define script colors
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

# Success message
success_message() {
    echo -e "${GREEN}[✔] $1${RESET}"
}

# Error message
error_message() {
    echo -e "${RED}[✘] $1${RESET}"
}

# Info message
info_message() {
    echo -e "${YELLOW}[ℹ] $1${RESET}"
}

# Section separator
separator() {
    echo -e "\n${CYAN}=============================================================${RESET}"
    echo -e "${CYAN}>>> $1 <<<${RESET}"
    echo -e "${CYAN}=============================================================${RESET}\n"
}

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate port number
validate_port() {
    local port=$1
    if [[ $port =~ ^[0-9]+$ ]] && [ $port -ge 1 ] && [ $port -le 65535 ]; then
        return 0
    else
        return 1
    fi
}

# Function to setup WireGuard client
setup_wireguard_client() {

   separator "System Update"
    info_message "Updating system packages..."
    apt update && apt upgrade -y || {
        error_message "System update failed"
        exit 1
    }
    success_message "System updated successfully"

    separator "WireGuard Client Setup"

    # Check if WireGuard is installed
    if ! command -v wg &> /dev/null; then
        info_message "Installing WireGuard..."
        if [ -f /etc/debian_version ]; then
            apt update && apt install -y wireguard wireguard-tools || {
                error_message "Failed to install WireGuard"
                exit 1
            }
        elif [ -f /etc/fedora-release ]; then
            dnf install -y wireguard-tools || {
                error_message "Failed to install WireGuard"
                exit 1
            }
        else
            error_message "Unsupported distribution"
            exit 1
        fi
        success_message "WireGuard installed successfully"
    fi

    # Get server information
    separator "Server Information"
    read -p "Enter server public IP: " SERVER_IP
    if ! validate_ip "$SERVER_IP"; then
        error_message "Invalid IP address format"
        exit 1
    fi

    read -p "Enter server port (default: 51820): " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-51820}
    if ! validate_port "$SERVER_PORT"; then
        error_message "Invalid port number"
        exit 1
    fi

    read -p "Enter server public key: " SERVER_PUBKEY
    if [ -z "$SERVER_PUBKEY" ]; then
        error_message "Server public key cannot be empty"
        exit 1
    fi

    # Create client configuration directory
    separator "Client Configuration"
    CLIENT_DIR="/etc/wireguard"
    mkdir -p "$CLIENT_DIR"

    # Generate client keys
    info_message "Generating client keys..."
    cd "$CLIENT_DIR" || {
        error_message "Failed to access $CLIENT_DIR"
        exit 1
    }

    wg genkey | tee privatekey | wg pubkey > publickey
    local PRIVATE_KEY=$(cat privatekey)
    
    # Create client configuration
    info_message "Creating client configuration..."
    cat > "$CLIENT_DIR/wg0.conf" << EOF
[Interface]
PrivateKey = ${PRIVATE_KEY}
Address = 10.10.10.2/24
DNS = 8.8.8.8, 8.8.4.4

[Peer]
PublicKey = ${SERVER_PUBKEY}
AllowedIPs = 0.0.0.0/0
Endpoint = ${SERVER_IP}:${SERVER_PORT}
PersistentKeepalive = 25
EOF

    chmod 600 "$CLIENT_DIR/wg0.conf"
    success_message "Client configuration created successfully"

    # Enable and start WireGuard service
    separator "Service Setup"
    info_message "Enabling and starting WireGuard service..."
    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0

    if systemctl is-active --quiet wg-quick@wg0; then
        success_message "WireGuard service started successfully"
    else
        error_message "Failed to start WireGuard service"
        exit 1
    fi

    separator "Setup Complete"
    success_message "WireGuard client setup completed successfully!"
    info_message "Client public key: $(cat publickey)"
    info_message "Configuration file location: $CLIENT_DIR/wg0.conf"
    wg show wg0
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    error_message "Please run as root"
    exit 1
fi

# Main execution
setup_wireguard_client