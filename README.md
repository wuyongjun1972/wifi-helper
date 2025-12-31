# WiFi Helper for macOS

A menu-driven and command-line Wi-Fi management tool for macOS that helps you manage preferred networks and retrieve stored passwords.

## Features

- **Interactive Menu Mode**: User-friendly menu for common Wi-Fi tasks
- **Non-Interactive Mode**: Command-line flags for automation and scripting
- **Auto-Detection**: Automatically detects Wi-Fi interface (en0, en1, etc.)
- **Password Retrieval**: Shows stored passwords from macOS Keychain
- **Network Management**: List preferred networks and add new ones
- **JSON Output**: Optional JSON format for integration with other tools
- **File Output**: Save results to files for logging or processing

## Requirements

- macOS 10.10 or later
- Command-line tools (networksetup, security)
- Administrator privileges for Keychain access

## Installation

1. Download the script:
```bash
curl -O https://raw.githubusercontent.com/YOUR_USERNAME/wifi-helper/main/wifi-helper.sh
```

2. Make it executable:
```bash
chmod +x wifi-helper.sh
```

## Usage

### Interactive Mode (Default)

Simply run the script to access the interactive menu:

```bash
./wifi-helper.sh
```

### Non-Interactive Mode

#### List all preferred Wi-Fi networks:
```bash
./wifi-helper.sh --non-interactive --action list-ssids
```

#### List networks as JSON:
```bash
./wifi-helper.sh --non-interactive --action list-ssids --json
```

#### Show password for a specific network:
```bash
./wifi-helper.sh --non-interactive --action show-password --ssid "MyWiFi"
```

#### Save output to file:
```bash
./wifi-helper.sh --non-interactive --action list-ssids --json --output networks.json
```

## Command-Line Options

- `-h, --help`: Show help message
- `--non-interactive`: Run without interactive menu
- `--action ACTION`: Specify action (`list-ssids` or `show-password`)
- `--ssid NAME`: Target SSID for password retrieval
- `--json`: Output in JSON format
- `--output FILE`: Save output to specified file

## Security Notes

- macOS will prompt for permission to access passwords in Keychain
- Intended for administrative use on your own Mac
- Passwords are retrieved from the system Keychain using the `security` command

## Examples

### Get all network names in JSON format:
```bash
./wifi-helper.sh --non-interactive --action list-ssids --json
```

### Retrieve password for home network:
```bash
./wifi-helper.sh --non-interactive --action show-password --ssid "Home-WiFi"
```

### Log all networks to a file:
```bash
./wifi-helper.sh --non-interactive --action list-ssids --output my-networks.txt
```

## Error Handling

The script includes comprehensive error handling with:
- OS compatibility checks
- Version verification
- Command availability validation
- Graceful error messages with troubleshooting hints

## License

MIT License - Feel free to use and modify as needed.
