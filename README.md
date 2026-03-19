# Cloudflare AAAA (IPv6) Dynamic DNS Updater

A PowerShell script that automatically updates AAAA (IPv6) DNS records in Cloudflare. It fetches the current public IPv6 address and ensures the configured hostname in Cloudflare has the correct IPv6 address.

## Features

- **Automatic IPv6 Detection**: Fetches your current public IPv6 address from the internet
- **DNS Record Management**: Creates, updates, or removes AAAA records as needed
- **Duplicate Handling**: Removes duplicate AAAA records automatically
- **Pagination Support**: Handles large numbers of DNS records efficiently
- **Validation**: Validates IPv6 addresses and API responses
- **Verbose Logging**: Provides detailed logging for troubleshooting
- **Dry Run Mode**: Preview changes without making them using the `-WhatIf` parameter
- **Interactive Mode**: Get confirmation before each change using the `-Confirm` parameter

## Requirements

- PowerShell 5.1 or later
- Cloudflare API token with DNS edit permissions
- IPv6 internet connectivity

## Installation

1. Clone this repository or download the `cloudflareAAAA.ps1` script
2. Create a `secrets.json` file based on the `example_secrets.json` template
3. Fill in your Cloudflare credentials and configuration

## Configuration

Create a `secrets.json` file with the following properties:

```json
{
    "HOSTNAME": "example.com",
    "APIKEY": "your_cloudflare_api_token",
    "CLOUDFLARE_ZONE_ID": "your_zone_id"
}
```

Optional properties:

- `IPv6CheckURL`: Custom URL to fetch public IPv6 address (default: `https://v6.ipinfo.io/ip`)

## Usage

```powershell
# Basic usage
.\.\cloudflareAAAA.ps1

# With custom secrets file
.\.\cloudflareAAAA.ps1 -SecretsFile "./secrets.json"

# With verbose logging
.\.\cloudflareAAAA.ps1 -SecretsFile "./secrets.json" -Verbose

# Dry run - preview changes without making them
.\.\cloudflareAAAA.ps1 -SecretsFile "./secrets.json" -WhatIf

# Interactive mode - confirm each change
.\.\cloudflareAAAA.ps1 -SecretsFile "./secrets.json" -Confirm
```

## How It Works

1. Fetches your current public IPv6 address from the configured check URL
2. Retrieves all DNS records from your Cloudflare zone
3. Filters for AAAA records matching your configured hostname
4. Creates a new AAAA record if none exists (respects `-WhatIf` and `-Confirm`)
5. Updates the existing AAAA record if the IP has changed (respects `-WhatIf` and `-Confirm`)
6. Removes any duplicate AAAA records (respects `-WhatIf` and `-Confirm`)
7. Validates all API responses and handles errors appropriately

## Error Handling

The script includes comprehensive error handling for:
- Invalid IPv6 addresses
- API timeouts and failures
- Missing or invalid configuration
- Rate limiting and authentication errors

## License

This project is open source and available under the MIT License.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## Support

For issues or questions, please open a GitHub issue.
