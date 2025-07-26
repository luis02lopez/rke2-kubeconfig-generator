#!/bin/bash

# RKE2 Kubeconfig Generator
# Pure bash script that connects to RKE2 server via SSH, extracts kubeconfig,
# and merges it with local kubeconfig file.

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Default values
readonly DEFAULT_SSH_USER="root"
readonly DEFAULT_RKE2_CONFIG_PATH="/etc/rancher/rke2/rke2.yaml"
readonly LOCAL_KUBECONFIG="$HOME/.kube/config"

# Global variables
SSH_USER="$DEFAULT_SSH_USER"
RKE2_CONFIG_PATH="$DEFAULT_RKE2_CONFIG_PATH"
SSH_KEY=""
SSH_PASSWORD=""

# Function to print colored output
print_status() {
    echo -e "${GREEN}✓${NC} $1" >&2
}

print_error() {
    echo -e "${RED}❌${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠️${NC} $1" >&2
}

print_info() {
    echo -e "${BLUE}ℹ️${NC} $1" >&2
}

# Function to show usage
show_usage() {
    cat << EOF
RKE2 Kubeconfig Generator

Usage: $0 <server_ip> <cluster_name> [options]

Arguments:
  server_ip      IP address or hostname of the RKE2 server
  cluster_name   Name to assign to the cluster in kubeconfig

Options:
  --ssh-user USER        SSH username (default: root)
  --ssh-key PATH         Path to SSH private key file
  --ssh-password PASS    SSH password (requires sshpass)
  --rke2-config PATH     Path to RKE2 kubeconfig on remote server (default: /etc/rancher/rke2/rke2.yaml)
  --help                 Show this help message

Examples:
  $0 192.168.1.100 my-cluster --ssh-key ~/.ssh/id_rsa
  $0 192.168.1.100 my-cluster --ssh-password mypassword
  $0 192.168.1.100 my-cluster --ssh-user ubuntu

EOF
}

# Function to validate cluster name
validate_cluster_name() {
    local name=$1
    [[ $name =~ ^[a-zA-Z0-9_-]+$ ]]
}

# Function to validate file exists
validate_file() {
    local file=$1
    [[ -f "$file" ]]
}

# Function to build SSH command
build_ssh_cmd() {
    local ssh_cmd="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30"
    
    if [[ -n "$SSH_KEY" ]]; then
        if ! validate_file "$SSH_KEY"; then
            print_error "SSH key file not found: $SSH_KEY"
            exit 1
        fi
        ssh_cmd="$ssh_cmd -i $SSH_KEY"
    fi
    
    if [[ -n "$SSH_PASSWORD" ]]; then
        if ! command -v sshpass &> /dev/null; then
            print_error "sshpass is required for password authentication. Install with: brew install sshpass"
            exit 1
        fi
        ssh_cmd="sshpass -p '$SSH_PASSWORD' $ssh_cmd"
    fi
    
    echo "$ssh_cmd"
}

# Function to extract kubeconfig from remote server
extract_remote_kubeconfig() {
    local server_ip=$1
    local ssh_cmd=$(build_ssh_cmd)
    
    print_info "Connecting to RKE2 server at $server_ip..."
    
    # Check if RKE2 config exists
    if ! $ssh_cmd "$SSH_USER@$server_ip" "test -f $RKE2_CONFIG_PATH"; then
        print_error "RKE2 kubeconfig not found at $RKE2_CONFIG_PATH"
        exit 1
    fi
    
    # Read the kubeconfig file
    local kubeconfig_content
    kubeconfig_content=$($ssh_cmd "$SSH_USER@$server_ip" "cat $RKE2_CONFIG_PATH")
    
    if [[ -z "$kubeconfig_content" ]]; then
        print_error "Kubeconfig file is empty"
        exit 1
    fi
    
    print_status "Successfully extracted kubeconfig from remote server"
    echo "$kubeconfig_content"
}

# Function to clean YAML content
clean_yaml_content() {
    local content=$1
    echo "$content" | tr -d '\r' | sed 's/[[:cntrl:]]//g'
}

# Function to modify kubeconfig content
modify_kubeconfig() {
    local kubeconfig_content=$1
    local server_ip=$2
    local cluster_name=$3
    
    # Clean the content
    local clean_content=$(clean_yaml_content "$kubeconfig_content")
    
    # Use yq for YAML manipulation if available
    if command -v yq &> /dev/null; then
        local temp_file=$(mktemp)
        echo "$clean_content" > "$temp_file"
        
        yq eval "
            .clusters[0].name = \"$cluster_name\" |
            .clusters[0].cluster.server = \"https://$server_ip:6443\" |
            .contexts[0].name = \"$cluster_name\" |
            .contexts[0].context.cluster = \"$cluster_name\" |
            .contexts[0].context.user = \"$cluster_name-user\" |
            .users[0].name = \"$cluster_name-user\" |
            .\"current-context\" = \"$cluster_name\"
        " "$temp_file" 2>/dev/null || {
            print_warning "yq failed, using sed fallback"
            rm "$temp_file"
            echo "$clean_content" | sed -e "s/name: default/name: $cluster_name/g" \
                -e "s/localhost/$server_ip/g" \
                -e "s/127.0.0.1/$server_ip/g" \
                -e "s/cluster: default/cluster: $cluster_name/g" \
                -e "s/context: default/context: $cluster_name/g" \
                -e "s/user: default/user: $cluster_name-user/g" \
                -e "s/current-context: default/current-context: $cluster_name/g"
        }
        rm -f "$temp_file"
    else
        print_warning "yq not found, using sed. Install yq for better YAML handling: brew install yq"
        echo "$clean_content" | sed -e "s/name: default/name: $cluster_name/g" \
            -e "s/localhost/$server_ip/g" \
            -e "s/127.0.0.1/$server_ip/g" \
            -e "s/context: default/context: $cluster_name/g" \
            -e "s/user: default/user: $cluster_name-user/g" \
            -e "s/current-context: default/current-context: $cluster_name/g"
    fi
}

# Function to merge kubeconfigs
merge_kubeconfigs() {
    local existing_config=$1
    local new_config=$2
    local output_file=$3
    
    # Try kubectl merge first
    if command -v kubectl &> /dev/null; then
        local temp_existing=$(mktemp)
        local temp_new=$(mktemp)
        
        echo "$existing_config" > "$temp_existing"
        echo "$new_config" > "$temp_new"
        
        if KUBECONFIG="$temp_existing:$temp_new" kubectl config view --flatten > "$output_file" 2>/dev/null; then
            rm "$temp_existing" "$temp_new"
            return 0
        fi
        rm "$temp_existing" "$temp_new"
    fi
    
    # Try yq merge
    if command -v yq &> /dev/null; then
        local temp_existing=$(mktemp)
        local temp_new=$(mktemp)
        
        echo "$existing_config" > "$temp_existing"
        echo "$new_config" > "$temp_new"
        
        if yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$temp_existing" "$temp_new" > "$output_file" 2>/dev/null; then
            rm "$temp_existing" "$temp_new"
            return 0
        fi
        rm "$temp_existing" "$temp_new"
    fi
    
    # Fallback: append new config to existing
    echo "$existing_config" > "$output_file"
    echo "" >> "$output_file"
    echo "$new_config" >> "$output_file"
    return 0
}

# Function to merge with local kubeconfig
merge_with_local_kubeconfig() {
    local new_config=$1
    local cluster_name=$2
    
    # Create ~/.kube directory if it doesn't exist
    mkdir -p "$(dirname "$LOCAL_KUBECONFIG")"
    
    # If local kubeconfig exists, merge with it
    if [[ -f "$LOCAL_KUBECONFIG" ]]; then
        # Create backup
        cp "$LOCAL_KUBECONFIG" "$LOCAL_KUBECONFIG.backup"
        print_warning "Created backup at $LOCAL_KUBECONFIG.backup"
        
        # Read existing config
        local existing_config=$(cat "$LOCAL_KUBECONFIG")
        
        # Merge configurations
        local temp_merged=$(mktemp)
        if merge_kubeconfigs "$existing_config" "$new_config" "$temp_merged"; then
            mv "$temp_merged" "$LOCAL_KUBECONFIG"
            print_status "Successfully merged kubeconfigs"
        else
            print_error "Failed to merge kubeconfigs"
            rm -f "$temp_merged"
            exit 1
        fi
    else
        # No existing kubeconfig, just use the new one
        echo "$new_config" > "$LOCAL_KUBECONFIG"
        print_status "Created new kubeconfig file"
    fi
    
    # Verify the context was created
    if command -v kubectl &> /dev/null; then
        if kubectl config get-contexts "$cluster_name" &>/dev/null; then
            print_status "Context '$cluster_name' successfully created"
        else
            print_warning "Context creation may have failed"
        fi
    fi
}

# Function to test connection
test_connection() {
    local cluster_name=$1
    
    print_info "Testing connection..."
    
    if command -v kubectl &> /dev/null; then
        if kubectl cluster-info --context "$cluster_name" &>/dev/null; then
            print_status "Connection test successful"
        else
            print_warning "Connection test failed, but kubeconfig was created"
            print_info "Test manually with: kubectl cluster-info --context $cluster_name"
        fi
    else
        print_warning "kubectl not found. Install kubectl to test the connection."
    fi
}

# Main function
main() {
    # Parse command line arguments
    if [[ $# -lt 2 ]]; then
        show_usage
        exit 1
    fi
    
    local server_ip=$1
    local cluster_name=$2
    shift 2
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ssh-user)
                SSH_USER="$2"
                shift 2
                ;;
            --ssh-key)
                SSH_KEY="$2"
                shift 2
                ;;
            --ssh-password)
                SSH_PASSWORD="$2"
                shift 2
                ;;
            --rke2-config)
                RKE2_CONFIG_PATH="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate inputs
    if ! validate_cluster_name "$cluster_name"; then
        print_error "Invalid cluster name: $cluster_name (use only letters, numbers, hyphens, and underscores)"
        exit 1
    fi
    
    # Extract kubeconfig from remote server
    local kubeconfig_content
    kubeconfig_content=$(extract_remote_kubeconfig "$server_ip")
    
    # Modify kubeconfig
    local modified_config
    modified_config=$(modify_kubeconfig "$kubeconfig_content" "$server_ip" "$cluster_name")
    print_status "Modified kubeconfig for cluster '$cluster_name'"
    
    # Merge with local kubeconfig
    merge_with_local_kubeconfig "$modified_config" "$cluster_name"
    
    # Test connection
    test_connection "$cluster_name"
    
    print_status "RKE2 kubeconfig generation completed successfully!"
}

# Run main function with all arguments
main "$@" 