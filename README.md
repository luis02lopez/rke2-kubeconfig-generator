# RKE2 Kubeconfig Generator

A pure bash script that securely connects to an RKE2 server via SSH, extracts the kubeconfig, and intelligently merges it with your local kubeconfig file.

## ✨ Features

- 🚀 **Pure Bash**: No Python dependencies required
- 🔐 **Multiple SSH Auth Methods**: SSH key and password authentication
- 🧠 **Smart Merging**: Intelligently merges with existing kubeconfig and replaces clusters with same name
- 🔄 **Auto-Replacement**: Automatically replaces existing cluster credentials with new ones
- 💾 **Backup Protection**: Automatically creates backups before modifications
- 🧪 **Connection Testing**: Validates the connection after setup
- 🎨 **Colored Output**: Clear status messages with intuitive colors
- 🛡️ **Robust Error Handling**: Comprehensive validation and error recovery
- 🔧 **Flexible Configuration**: Customizable SSH options and RKE2 paths

## 🚀 Quick Start

### Make executable and run:
```bash
chmod +x main.sh
./main.sh <server_ip> <cluster_name> [options]
```

## 📖 Examples

### Using SSH key authentication (recommended)
```bash
./main.sh 192.168.1.100 my-cluster --ssh-key ~/.ssh/id_rsa
```

### Using password authentication
```bash
./main.sh 192.168.1.100 my-cluster --ssh-password mypassword
```

### Using custom SSH user
```bash
./main.sh 192.168.1.100 my-cluster --ssh-user ubuntu
```

### Custom RKE2 config path
```bash
./main.sh 192.168.1.100 my-cluster --rke2-config /custom/path/rke2.yaml
```

## 📋 Command Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `server_ip` | IP address or hostname of the RKE2 server | **Required** |
| `cluster_name` | Name to assign to the cluster in kubeconfig | **Required** |
| `--ssh-user` | SSH username | `root` |
| `--ssh-key` | Path to SSH private key file | None |
| `--ssh-password` | SSH password (requires sshpass) | None |
| `--rke2-config` | Path to RKE2 kubeconfig on remote server | `/etc/rancher/rke2/rke2.yaml` |
| `--help` | Show help message | - |

## 📦 Dependencies

### Required
- `bash` - Shell interpreter
- `ssh` - SSH client
- `sed` - Text processing (usually pre-installed)

### Optional (for enhanced features)
- `yq` - Better YAML processing and merging
- `kubectl` - For proper kubeconfig merging and connection testing
- `sshpass` - For password authentication

### Installation
```bash
# macOS
brew install yq kubectl sshpass

# Ubuntu/Debian
sudo apt-get install yq kubectl sshpass

# CentOS/RHEL
sudo yum install yq kubectl sshpass
```

## 🔧 How It Works

### 1. **SSH Connection**
- Validates SSH credentials and connection parameters
- Connects to the RKE2 server using provided authentication method
- Verifies the RKE2 kubeconfig file exists

### 2. **Extract Kubeconfig**
- Securely reads the RKE2 kubeconfig from the remote server
- Validates the content is not empty
- Handles connection timeouts and errors gracefully

### 3. **Modify Configuration**
- Cleans YAML content to remove control characters
- Replaces localhost/127.0.0.1 with the actual server IP
- Updates cluster, context, and user names with your provided cluster name
- Uses `yq` for precise YAML manipulation with `sed` fallback

### 4. **Smart Merging Strategy**
The script uses a multi-tiered approach to merge configurations with automatic replacement:

1. **kubectl merge with replacement** (preferred) - Removes existing cluster entries and merges new config
2. **yq merge** (backup) - Uses YAML-aware merging with `yq eval-all`
3. **Replace** (fallback) - Replaces existing config with new one to ensure fresh credentials

### 5. **Validation & Testing**
- Creates automatic backups before modifications
- Verifies context creation was successful
- Tests the connection using `kubectl cluster-info`
- Provides clear feedback on success/failure

## 🛠️ Troubleshooting

### SSH Connection Issues
```bash
# Test SSH connection manually
ssh user@server_ip

# Check SSH key permissions
chmod 600 ~/.ssh/id_rsa

# Verify RKE2 service is running
ssh user@server_ip "systemctl status rke2-server"
```

### Password Authentication
If using password authentication, ensure `sshpass` is installed:
```bash
# macOS
brew install sshpass

# Ubuntu/Debian
sudo apt-get install sshpass
```

### YAML Processing Issues
For better YAML handling, install `yq`:
```bash
# macOS
brew install yq

# Ubuntu/Debian
sudo apt-get install yq
```

### Kubeconfig Issues
```bash
# Verify RKE2 config exists
ssh user@server_ip "ls -la /etc/rancher/rke2/rke2.yaml"

# Check firewall allows Kubernetes API access
ssh user@server_ip "netstat -tlnp | grep :6443"

# Test kubectl locally
kubectl version --client
```

### Common Error Solutions

| Error | Solution |
|-------|----------|
| `sshpass is required` | Install sshpass: `brew install sshpass` |
| `yq not found` | Install yq: `brew install yq` |
| `SSH key file not found` | Check path and permissions: `chmod 600 ~/.ssh/id_rsa` |
| `RKE2 kubeconfig not found` | Verify RKE2 is installed and running on the server |
| `Connection test failed` | Check firewall rules and network connectivity |

## 🔒 Security Considerations

- **SSH Keys**: Use SSH key authentication instead of passwords when possible
- **Key Permissions**: Ensure SSH keys have correct permissions (`chmod 600`)
- **Network Security**: Verify the RKE2 server is accessible and properly secured
- **Backup Files**: Backup files are created automatically but should be reviewed periodically

## 📁 Files

- `main.sh` - The main bash script
- `README.md` - This documentation

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is open source and available under the [MIT License](LICENSE). 