<#
.SYNOPSIS
Dynamic DNS updater for Cloudflare AAAA (IPv6) records.

.DESCRIPTION
PowerShell script that automatically updates AAAA (IPv6) DNS records in Cloudflare.
It fetches the current public IPv6 address from the internet and ensures the configured hostname
in Cloudflare has the correct IPv6 address. If no record exists, it creates one. If the record
exists but has a different IP, it updates it. If multiple records exist, it removes duplicates.

.PARAMETER SecretsFile
Path to the JSON file containing Cloudflare credentials and configuration.
Defaults to ./secrets.json in the script directory.

.NOTES
Required secrets.json properties:
- HOSTNAME: The DNS hostname to manage (e.g., 'example.com')
- APIKEY: Cloudflare API token with DNS edit permissions
- CLOUDFLARE_ZONE_ID: The Cloudflare zone ID for the domain

Optional secrets.json properties:
- IPv6CheckURL: Custom URL to fetch public IPv6 address (default: https://v6.ipinfo.io/ip)

.EXAMPLE
.\cloudflareAAAA.ps1 -SecretsFile "./secrets.json" -Verbose
#>

[cmdletbinding()]
Param(
    [Parameter()][String]$SecretsFile = "./secrets.json"
)

# ===========================
# Helper Functions
# ===========================

<#
.SYNOPSIS
Fetches all DNS records from a Cloudflare zone with pagination support.

.DESCRIPTION
Retrieves all DNS records from the specified Cloudflare zone using the API.
Implements pagination to automatically fetch all pages of results, combining them
into a single array before returning.

.PARAMETER secrets
PSCustomObject containing secrets with properties: APIKEY and CLOUDFLARE_ZONE_ID

.OUTPUTS
Array of all DNS record objects from Cloudflare API across all pages
#>
function fetch_all_dns() {
    param(
        [Parameter(Mandatory)][PSCustomObject]$secrets
    )
    
    $allRecords = @()
    $page = 1
    $perPage = 100  # Max results per page (Cloudflare max is 500, but 100 is reasonable)
    $baseUri = "https://api.cloudflare.com/client/v4/zones/$($secrets.CLOUDFLARE_ZONE_ID)/dns_records"
    $headers = @{'Authorization' = "Bearer $($secrets.APIKEY)"}
    
    # Loop through all pages of results
    do {
        Write-Verbose -Message "Fetching DNS records page $page (up to $perPage records per page)"
        
        # Build URI with pagination parameters
        $uri = "$baseUri`?page=$page&per_page=$perPage"
        
        # Fetch the current page of results
        $response = Invoke-WebRequest -Method Get -Uri $uri -Headers $headers -Verbose:$false
        $jsonResponse = $response.Content | ConvertFrom-Json
        
        # Get the records from this page
        $pageRecords = $jsonResponse.result
        $allRecords += $pageRecords
        
        Write-Verbose -Message "Retrieved $($pageRecords.Count) records from page $page"
        
        # Check if there are more pages
        $totalCount = $jsonResponse.result_info.total_count
        $pages = $jsonResponse.result_info.total_pages
        
        Write-Verbose -Message "Total records available: $totalCount across $pages pages"
        
        $page++
        
    } while ($page -le $pages)
    
    Write-Verbose -Message "Finished pagination. Retrieved total of $($allRecords.Count) DNS records"
    return $allRecords
}

<#
.SYNOPSIS
Creates a new AAAA DNS record in Cloudflare.

.DESCRIPTION
Creates a new AAAA (IPv6) DNS record with the public IPv6 address from the secrets object.
Includes a comment to identify records created by this script.

.PARAMETER secrets
PSObject containing: APIKEY, CLOUDFLARE_ZONE_ID, HOSTNAME, and IPv6

.OUTPUTS
The newly created DNS record object from Cloudflare API
#>
function create_dns_post() {
    param(
        [Parameter(Mandatory)][PSObject]$secrets
    )
    # Prepare the DNS record payload
    $myData = @{
        "type"="AAAA"
        "name"=$secrets.HOSTNAME
        "content"=$secrets.IPv6
        "comment"="Added by Gnutt's CloudFlare AAAA DynDNS"
    }
    # POST request to create the new DNS record
    $data = Invoke-WebRequest -Method Post -Uri "https://api.cloudflare.com/client/v4/zones/$($secrets.CLOUDFLARE_ZONE_ID)/dns_records" -Headers @{'Authorization' = "Bearer $($secrets.APIKEY)"} -Body ($myData | ConvertTo-Json) -Verbose:$false
    return ($data.Content | ConvertFrom-Json).result
}

<#
.SYNOPSIS
Updates an existing AAAA DNS record in Cloudflare.

.DESCRIPTION
Updates an AAAA (IPv6) DNS record with the current public IPv6 address.
Uses the record ID to target the specific record to update.

.PARAMETER secrets
PSObject containing: APIKEY, CLOUDFLARE_ZONE_ID, HOSTNAME, and IPv6

.PARAMETER id
The Cloudflare DNS record ID to update

.OUTPUTS
The updated DNS record object from Cloudflare API
#>
function update_dns_post() {
    param(
        [Parameter(Mandatory)][PSObject]$secrets,
        [Parameter(Mandatory)][String]$id
    )
    # Prepare the updated DNS record payload
    $myData = @{
        "type"="AAAA"
        "name"=$secrets.HOSTNAME
        "content"=$secrets.IPv6
        "comment"="Added by Gnutt's CloudFlare AAAA DynDNS"
    }
    # PATCH request to update the existing DNS record
    $data = Invoke-WebRequest -Method Patch -Uri "https://api.cloudflare.com/client/v4/zones/$($secrets.CLOUDFLARE_ZONE_ID)/dns_records/$($id)" -Headers @{'Authorization' = "Bearer $($secrets.APIKEY)"; 'Content-Type' = 'application/json'} -Body ($myData | ConvertTo-Json) -Verbose:$false
    return ($data.Content | ConvertFrom-Json).result
}

<#
.SYNOPSIS
Deletes an AAAA DNS record from Cloudflare.

.DESCRIPTION
Removes a DNS record from the Cloudflare zone by its record ID.
Used to clean up duplicate or obsolete records.

.PARAMETER secrets
PSObject containing: APIKEY and CLOUDFLARE_ZONE_ID

.PARAMETER id
The Cloudflare DNS record ID to delete

.OUTPUTS
The deleted DNS record object from Cloudflare API
#>
function remove_dns_post() {
    param(
        [Parameter(Mandatory)][PSObject]$secrets,
        [Parameter(Mandatory)][String]$id
    )
    # DELETE request to remove the DNS record
    $data = Invoke-WebRequest -Method Delete -Uri "https://api.cloudflare.com/client/v4/zones/$($secrets.CLOUDFLARE_ZONE_ID)/dns_records/$($id)" -Headers @{'Authorization' = "Bearer $($secrets.APIKEY)"} -Verbose:$false
    return ($data.Content | ConvertFrom-Json).result
}

<#
.SYNOPSIS
Gets the directory where the script is located.

.DESCRIPTION
Returns the full path of the directory containing the currently executing script.
Used to resolve relative paths for the secrets file.

.OUTPUTS
String containing the script directory path
#>
function Get-ScriptDirectory
{
  $Invocation = (Get-Variable MyInvocation -Scope 1).Value
  Split-Path $Invocation.MyCommand.Path
}

# ===========================
# Main Script Logic
# ===========================

# Enable verbose output if -Verbose flag is passed
if($Verbose) {
    $VerbosePreference = "Continue"
    Write-Verbose -Message "Enabling Verbose Output"
}

# STEP 1: Locate and validate the secrets file
if( !(Resolve-Path $SecretsFile -ErrorAction SilentlyContinue )) {
    Write-Verbose "Could not find secrets file at $($SecretsFile), trying with script directory attached"
    $SecretsFile = Join-Path -Path (Get-ScriptDirectory) -ChildPath $SecretsFile -ErrorAction SilentlyContinue
    if( !(Resolve-Path $SecretsFile -ErrorAction SilentlyContinue )) {
        throw "Could not find the secrets file"
    } else {
        $SecretsFile = Resolve-Path $SecretsFile
        Write-Verbose "Found it at $($SecretsFile)"
    }
}

Write-Verbose -Message "Loading Secrets from $($SecretsFile)"
$secrets = Get-Content $SecretsFile | ConvertFrom-Json
$MANDATORY_SECRETS="HOSTNAME", "APIKEY", "CLOUDFLARE_ZONE_ID"

# STEP 2: Validate that all required properties exist in secrets file
Write-Verbose -Message "Verifying all required secrets exists"
foreach($attr in $MANDATORY_SECRETS) {
    if(! (Get-Member -InputObject $secrets -Name $attr)) {
        throw "Secrets is missing property $attr"
    }
}

# STEP 3: Set default IPv6 check URL if not provided in secrets
if(!(Get-Member -InputObject $secrets -Name "IPv6CheckURL")) # If there is no replacement IPv6 Check URL, use the default
{
    $secrets | Add-Member -MemberType NoteProperty -Name 'IPv6CheckURL' -Value "https://v6.ipinfo.io/ip"
}

# STEP 4: Fetch the current public IPv6 address from the internet
Write-Verbose -Message "Asked internet what the public IPv6 Address is"
$PublicIPV6 = (Invoke-WebRequest -Uri $secrets.IPv6CheckURL -Verbose:$false -ErrorAction Stop).Content
if(!$PublicIPV6) {throw "Could not fetch a good IPv6 Address for some reason"}
Write-Verbose -Message "It was $($PublicIPV6), storing it in the global secrets variable"
$secrets | Add-Member -MemberType NoteProperty -Name 'IPv6' -Value $PublicIPV6

# STEP 5: Fetch existing DNS records from Cloudflare
Write-Verbose -Message "Fetching all DNS posts"
$posts = fetch_all_dns -secrets $secrets

# STEP 6: Filter for matching AAAA records
Write-Verbose -Message "Filtering posts for only matching name $($secrets.HOSTNAME) and type AAAA"
[Object[]]$filteredposts = $posts | Where-Object {$_.name -eq $secrets.HOSTNAME -and $_.type -eq "AAAA"}
Write-Verbose -Message "Still have $($filteredposts.Length) posts in the list"

# STEP 7: Create, update, or skip based on existing records
if($filteredposts.Length -eq 0) {
    # No existing record - create a new one
    Write-Verbose -Message "Creating a new DNS post"
    create_dns_post -secrets $secrets
} elseif( $filteredposts.Length -gt 0) {
    # Existing record(s) found - check if update is needed
    Write-Verbose -Message "Checking that first DNS post returned has correct IPv6 address [$($filteredposts[0].content) compared to stored $($PublicIPV6)]"
    if( $filteredposts[0].content -ne $secrets.IPv6 ) {
        # IP has changed - update the record
        Write-Verbose -Message "It did not, updating first DNS matching DNS post"
        update_dns_post -secrets $secrets -id $filteredposts[0].id
    } else {
        # IP matches - no action needed
        Write-Verbose "It matched, nothing to update!"
    }
}

# STEP 8: Clean up duplicate records (should only have one AAAA record)
if( $filteredposts.Length -gt 1) {
    Write-Verbose -Message "Too many DNS posts found (should only have one), deleting superfluous"
    # Keep the first record, delete the rest
    $first,[Object[]]$rest = $filteredposts
    foreach($post in $rest) {
        Write-Verbose -Message "Removing duplicate record with ID $($post.id)"
        remove_dns_post -secrets $secrets -id $post.id
    }
}

Write-Verbose -Message "Script execution completed successfully"
