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

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        error_message "Please run as root"
        exit 1
    fi
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

get_public_ip() {
    local public_ip=$(curl -s https://api.ipify.org)
    
    if [ -z "$public_ip" ]; then
        error_message "Failed to determine public IP address"
        exit 1
    fi
    
    echo "$public_ip"
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

    separator "installation of dependencies"
    info_message "Installing dependencies..."
    apt install curl -y || {
        error_message "curl install failed"
        exit 1
    }
    apt apt install resolvconf -y || {
        error_message "curl install failed"
        exit 1
    }
    success_message "installation of dependencies successfully"

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

    # Generate client keys
    separator "Key Generation"
    info_message "Generating client keys..."
    CLIENT_DIR="/etc/wireguard"
    mkdir -p "$CLIENT_DIR"

    cd "$CLIENT_DIR" || {
        error_message "Failed to access $CLIENT_DIR"
        exit 1
    }

    wg genkey | tee privatekey | wg pubkey > publickey
    local CLIENT_PRIVATE_KEY=$(cat privatekey)
    local CLIENT_PUBLIC_KEY=$(cat publickey)
    
    # Display the client's public key
     info_message "Client public key: $CLIENT_PUBLIC_KEY"

    # Get server information
    separator "Server Information"
    
    # Prompt user about server setup
    read -p "At this moment, your server must be configured. If this is your reality, write Yes to continue: " PROCEED
    if [[ "$PROCEED" != "Yes" && "$PROCEED" != "yes" ]]; then
        error_message "Setup aborted by user."
        exit 1
    fi

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

        read -p "Enter client private ip inside VPN: " PRIVATE_IP
    if [ -z "$PRIVATE_IP" ]; then
        error_message "Server public key cannot be empty"
        exit 1
    fi

    # Create client configuration
    separator "Client Configuration"
    info_message "Creating client configuration..."
    cat > "$CLIENT_DIR/wg0.conf" << EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${$PRIVATE_IP}
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

    separator "Actual Interface"
    wg show wg0

    local IP_PUBLIC=$(get_public_ip)

    separator "Setup Complete"
    success_message "WireGuard client setup completed successfully!"
    info_message "Configuration file location: $CLIENT_DIR/wg0.conf"
    info_message "My actual IP: $IP_PUBLIC"

}

# Main execution
check_root
setup_wireguard_client