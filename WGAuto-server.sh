#!/bin/bash

cat << "EOF"
╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗

$$\      $$\  $$$$$$\           $$$$$$\              $$\                      $$$$$$\                                                     
$$ | $\  $$ |$$  __$$\         $$  __$$\             $$ |                    $$  __$$\                                                    
$$ |$$$\ $$ |$$ /  \__|        $$ /  $$ |$$\   $$\ $$$$$$\    $$$$$$\        $$ /  \__| $$$$$$\   $$$$$$\  $$\    $$\  $$$$$$\   $$$$$$\  
$$ $$ $$\$$ |$$ |$$$$\ $$$$$$\ $$$$$$$$ |$$ |  $$ |\_$$  _|  $$  __$$\       \$$$$$$\  $$  __$$\ $$  __$$\ \$$\  $$  |$$  __$$\ $$  __$$\ 
$$$$  _$$$$ |$$ |\_$$ |\______|$$  __$$ |$$ |  $$ |  $$ |    $$ /  $$ |       \____$$\ $$$$$$$$ |$$ |  \__| \$$\$$  / $$$$$$$$ |$$ |  \__|
$$$  / \$$$ |$$ |  $$ |        $$ |  $$ |$$ |  $$ |  $$ |$$\ $$ |  $$ |      $$\   $$ |$$   ____|$$ |        \$$$  /  $$   ____|$$ |      
$$  /   \$$ |\$$$$$$  |        $$ |  $$ |\$$$$$$  |  \$$$$  |\$$$$$$  |      \$$$$$$  |\$$$$$$$\ $$ |         \$  /   \$$$$$$$\ $$ |      
\__/     \__| \______/         \__|  \__| \______/    \____/  \______/        \______/  \_______|\__|          \_/     \_______|\__|                                                 


   by: brennocm (https://github.com/brennocm/wg-auto)
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝  
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

# Function to get the main network interface
get_main_interface() {
    local interface=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [ -z "$interface" ]; then
        error_message "Could not determine main network interface"
        exit 1
    fi
    echo "$interface"
}

get_public_ip() {
    local public_ip=$(curl -s https://api.ipify.org)
    
    if [ -z "$public_ip" ]; then
        error_message "Failed to determine public IP address"
        exit 1
    fi
    
    echo "$public_ip"
}


# Function to enable IP forwarding
enable_ip_forwarding() {
    info_message "Enabling IP forwarding..."
    
    # Uncomment the IP forwarding line in sysctl.conf
    sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    
    # Apply changes
    if sysctl -p; then
        success_message "IP forwarding enabled successfully"
    else
        error_message "Failed to enable IP forwarding"
        exit 1
    fi
}

# Function to get the network address (IP/subnet)
get_network_address() {
    local interface="$1"
    local ip_address=$(ip -4 addr show "$interface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
    
    if [ -z "$ip_address" ]; then
        error_message "Could not determine IP address for $interface"
        exit 1
    fi
    
    echo "${ip_address%.*}.0/24"
}

# Main setup function
setup_wireguard() {
    local MAIN_INTERFACE=$(get_main_interface)
    local NETWORK_ADDRESS=$(get_network_address "$MAIN_INTERFACE")
    local WG_IP="10.10.10.1"  # WireGuard server IP
    local CLIENT_IP="10.10.10.2"  # First client IP
    local IP_PUBLIC=$(get_public_ip)

    separator "System Update"
    info_message "Updating system packages..."
    apt update && apt upgrade -y || {
        error_message "System update failed"
        exit 1
    }
    apt install curl -y
    success_message "System updated successfully"

    separator "WireGuard Installation"
    info_message "Installing WireGuard..."
    apt install -y wireguard wireguard-tools ipcalc || {
        error_message "WireGuard installation failed"
        exit 1
    }
    success_message "WireGuard installed successfully"

    separator "IP Forwarding Setup"
    enable_ip_forwarding

    separator "WireGuard Module Check"
    info_message "Checking WireGuard kernel module..."
    if ! lsmod | grep wireguard > /dev/null; then
        info_message "Loading WireGuard module..."
        modprobe wireguard || {
            error_message "Failed to load WireGuard module"
            exit 1
        }
    fi
    success_message "WireGuard module is loaded"

    separator "Key Generation"
    info_message "Generating WireGuard keys..."
    cd /etc/wireguard || {
        error_message "Failed to access /etc/wireguard directory"
        exit 1
    }
    
    wg genkey | tee privatekey | wg pubkey > publickey
    local PRIVATE_KEY=$(cat privatekey)
    
    separator "Configuration Setup"
    info_message "Creating WireGuard configuration..."
    
    cat > /etc/wireguard/wg0.conf << EOF
[Interface]
PrivateKey = ${PRIVATE_KEY} 
Address = ${WG_IP}/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${MAIN_INTERFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${MAIN_INTERFACE} -j MASQUERADE

EOF
    
    # Ask for the client's public key
    read -p "Enter client's public key: " CLIENT_PUBLIC_KEY
    
    # Add the peer configuration to the wg0.conf file
    echo "" >> /etc/wireguard/wg0.conf
    echo "[Peer]" >> /etc/wireguard/wg0.conf
    echo "PublicKey = $CLIENT_PUBLIC_KEY" >> /etc/wireguard/wg0.conf
    echo "AllowedIPs = $CLIENT_IP/32" >> /etc/wireguard/wg0.conf
    
    chmod 600 /etc/wireguard/wg0.conf
    success_message "Configuration file created successfully"

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

    separator "Setup Complete"
    success_message "WireGuard server setup completed successfully!"
    info_message "Public Server IP: $IP_PUBLIC"
    info_message "WireGuard port: 51820"
    info_message "Server public key: $(cat publickey)"
    info_message "Client private ip inside VPN: $CLIENT_IP"
    info_message "To add more clients, edit /etc/wireguard/wg0.conf and add more [Peer] sections"
}

# Main execution
check_root
setup_wireguard