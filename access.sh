#!/bin/bash

# MLDS SSH Access Setup Script
# This script automates SSH key setup for MLDS server access
# It generates SSH keys, copies them to the NFS server, and updates SSH config
# Created specifically for Northwestern University NetID authentication

# Colors for output
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print status messages
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Function to print success messages
print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to print error messages
print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to print warning messages
print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if a command succeeded
check_status() {
    if [ $? -eq 0 ]; then
        print_success "$1"
        return 0
    else
        print_error "$2"
        return 1
    fi
}

print_status "Starting MLDS SSH Access Setup Script"

# Step 1: Check for SSH and related tools
print_status "Checking required tools"
if ! command -v ssh > /dev/null || ! command -v ssh-keygen > /dev/null || ! command -v ssh-copy-id > /dev/null; then
    print_error "SSH tools not found. Please install OpenSSH."
    exit 1
fi

print_success "Required tools found"

# Step 1.5: Check WiFi connection
print_status "Checking network connection..."

# Check for eduroam WiFi connection
print_status "Checking WiFi connection (this may take a few seconds)..."
WIFI_NAME=$(system_profiler SPAirPortDataType | awk '/Current Network/ {getline;$1=$1;print $0 | "tr -d \":\"";exit}')

if [ "$WIFI_NAME" == "eduroam" ]; then
    print_success "Connected to eduroam WiFi"
else
    print_warning "You don't see to be on eduroam WiFi. Network name: $WIFI_NAME"
    print_status "This script requires either eduroam WiFi or Northwestern VPN connection to work properly"
    print_status "If you are on Northwestern VPN or eduroam, you may continue"
    
    read -p "Are you connected to Northwestern VPN or eduroam? (y/n): " ON_VPN
    if [[ ! $ON_VPN =~ ^[Yy]$ ]]; then
        print_error "Not connected to Northwestern VPN or eduroam WiFi"
        print_status "Please connect to Northwestern VPN or eduroam WiFi before running this script"
        exit 1
    fi
    print_success "Continuing with Northwestern VPN connection"
fi

# Step 2: Try to determine NetID from SSH config
NETID=""
if [ -f ~/.ssh/config ]; then
    read -p "Please enter your Northwestern NetID: " NETID
    print_status "NetID set to: $NETID"
else
    print_warning "No SSH config found at ~/.ssh/config"
    print_status "An SSH config file helps you organize and simplify SSH connections."
    print_status "After this setup, we'll create one for you, but you might want to learn more about them."
    print_status "Tutorial: https://linuxize.com/post/using-the-ssh-config-file/"
    read -p "Please enter your Northwestern NetID: " NETID
    print_status "NetID set to: $NETID"
fi

# Validate NetID format (basic check)
if [[ ! $NETID =~ ^[a-z0-9]+$ ]]; then
    print_warning "NetID format looks unusual. Northwestern NetIDs typically contain only lowercase letters and numbers."
    read -p "Continue with this NetID? (y/n): " CONFIRM
    if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
        print_error "Exiting at user request"
        exit 1
    fi
fi

# Step 3: Generate SSH keys
KEY_NAME="mlds-access-$NETID"
KEY_PATH="$HOME/.ssh/$KEY_NAME"

print_status "Checking for existing SSH keys"
if [ -f "$KEY_PATH" ]; then
    print_warning "SSH key already exists at $KEY_PATH"
    read -p "Do you want to generate a new key and overwrite it? (y/n): " OVERWRITE
    if [[ ! $OVERWRITE =~ ^[Yy]$ ]]; then
        print_status "Using existing key"
    else
        print_status "Generating new SSH key pair"
        ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "MLDS access key for $NETID"
        check_status "SSH key pair generated" "Failed to generate SSH key pair"
    fi
else
    print_status "Generating new SSH key pair"
    # Create .ssh directory if it doesn't exist
    mkdir -p "$HOME/.ssh"
    ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "MLDS access key for $NETID"
    check_status "SSH key pair generated" "Failed to generate SSH key pair"
fi

# Fix permissions
chmod 600 "$KEY_PATH"
chmod 644 "$KEY_PATH.pub"
check_status "Set proper permissions on key files" "Failed to set proper permissions"

# Step 4: Copy SSH key to NFS
print_status "Copying SSH key to NFS storage"
print_status "You may be prompted for your Northwestern NetID password"

# Here we need to make sure the authorized_keys file exists with proper permissions
SSH_COPY_ID_CMD="ssh-copy-id -i $KEY_PATH.pub $NETID@mlds-deepdish4.ads.northwestern.edu"
eval $SSH_COPY_ID_CMD

# Here we need to make sure the authorized_keys file exists with proper permissions
SSH_COPY_ID_CMD="ssh-copy-id -i $KEY_PATH.pub $NETID@mlds-deepdish4.ads.northwestern.edu"
eval $SSH_COPY_ID_CMD
if [ $? -ne 0 ]; then
    print_error "Failed to copy SSH key to NFS. Please check your NetID and password."
    exit 1
fi
print_success "SSH key copied to NFS"
# Step 5: Update SSH config
print_status "Updating SSH config"

# Backup existing config if it exists
if [ -f ~/.ssh/config ]; then
    cp ~/.ssh/config ~/.ssh/config.backup.$(date +%Y%m%d%H%M%S)
    check_status "Backed up existing SSH config" "Failed to back up SSH config"
fi

# Ask for server nickname
read -p "Enter a nickname for the server (default: wolf): " SERVER_NICKNAME
SERVER_NICKNAME=${SERVER_NICKNAME:-wolf}

# Check if the entry already exists
if grep -q "Host $SERVER_NICKNAME" ~/.ssh/config 2>/dev/null; then
    print_warning "An entry for '$SERVER_NICKNAME' already exists in your SSH config"
    read -p "Do you want to update it? (y/n): " UPDATE_CONFIG
    if [[ $UPDATE_CONFIG =~ ^[Yy]$ ]]; then
        # Remove existing entry
        sed -i.bak "/Host $SERVER_NICKNAME/,/^\s*$/d" ~/.ssh/config
        check_status "Removed existing entry for $SERVER_NICKNAME" "Failed to update SSH config"
    else
        print_status "Skipping SSH config update"
    fi
fi

# Add new entry if needed
if [[ ! $UPDATE_CONFIG =~ ^[Nn]$ ]]; then
    # Ensure file exists
    touch ~/.ssh/config
    
    # Append new config
    cat >> ~/.ssh/config << EOF

Host $SERVER_NICKNAME
    HostName wolf.analytics.private
    User $NETID
    IdentityFile ~/.ssh/$KEY_NAME
EOF
    check_status "Updated SSH config" "Failed to update SSH config"
    
    # Fix permissions on config file
    chmod 600 ~/.ssh/config
fi

# Step 6: Test connection
print_status "Testing connection to the server"
print_status "Attempting to connect to test server and create a file. This will be deleted immediately."

TEST_COMMAND="ssh -i $KEY_PATH $NETID@irc.mlds.northwestern.edu 'touch ~/golden-ticket && ls -la ~/golden-ticket && rm ~/golden-ticket'"
eval "$TEST_COMMAND"

if [ $? -eq 0 ]; then
    print_success "Connection test passed. Your SSH key is working correctly"
    
    # Log successful setup to shared folder
    print_status "Logging successful setup"
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    HOST_INFO=$(uname -a)
    LOG_COMMAND="ssh -i $KEY_PATH $NETID@irc.mlds.northwestern.edu 'echo [$TIMESTAMP] Setup successful from $WIFI_NAME >> /nfs/home/shared/migration/${NETID}_$(date +%Y%m%d%H%M%S).log'"
    eval "$LOG_COMMAND" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        print_success "Setup logged successfully"
    else
        print_warning "Could not write to log file, but setup was successful"
    fi
else
    print_error "Connection test failed. Please check the following:"
    print_status "1. Ensure you entered the correct NetID"
    print_status "2. Make sure the NFS server is accessible"
    print_status "3. Verify that your account is properly set up on the server"
    print_status "4. Check if the server hostname 'wolf.analytics.private' resolves correctly"
    
    # Try with full hostname as a fallback
    print_status "Trying connection with full hostname as a fallback..."
    TEST_COMMAND="ssh -i $KEY_PATH $NETID@irc.mlds.northwestern.edu 'touch ~/golden-ticket && ls -la ~/golden-ticket && rm ~/golden-ticket'"
    eval "$TEST_COMMAND"
    
    if [ $? -eq 0 ]; then
        print_success "Connection successful using full hostname. Your SSH key works, but there might be an issue with your SSH config."
        
        # Log successful setup to shared folder
        print_status "Logging successful setup"
        TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
        LOG_COMMAND="ssh -i $KEY_PATH $NETID@irc.mlds.northwestern.edu 'echo [$TIMESTAMP] Setup successful from $WIFI_NAME >> /nfs/home/shared/migration/${NETID}_$(date +%Y%m%d%H%M%S).log'"
        eval "$LOG_COMMAND" > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            print_success "Setup logged successfully"
        else
            print_warning "Could not write to log file, but setup was successful"
        fi
    else
        print_error "Connection failed with full hostname as well. Please contact MLDS support for assistance."
    fi
fi

# Step 7: Ask for consent to collect telemetry
print_status "Setup complete!"
print_status "CAVEAT! The wolf server is not yet transitioned to local login!!"
print_status "Once the server *IS* transitioned to local login, simply type: ssh $SERVER_NICKNAME"
print_status "But if you try this now, it will still be slow or potentially fail."