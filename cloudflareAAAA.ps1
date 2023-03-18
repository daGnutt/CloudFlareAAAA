<#
.DESCRIPTION
Powershell script that takes a secrets file with Cloudflare information and posts the public IPv6 address you are accessing internet with as a host on cloudflare.
#>
[cmdletbinding()]
Param()

function fetch_all_dns() {
    param(
        [Parameter(Mandatory)][PSCustomObject]$secrets
    )
    #TODO Create pagination and fetching more pages if not all results is returned at once
    $data = Invoke-WebRequest -Method Get -Uri "https://api.cloudflare.com/client/v4/zones/$($secrets.CLOUDFLARE_ZONE_ID)/dns_records" -Headers @{'Authorization' = "Bearer $($secrets.APIKEY)"} -Verbose:$false
    return ($data.Content | ConvertFrom-Json).result
}

function create_dns_post() {
    param(
        [Parameter(Mandatory)][PSObject]$secrets
    )
    $myData = @{
        "type"="AAAA"
        "name"=$secrets.HOSTNAME
        "content"=$secrets.IPv6
        "comment"="Added by Gnutt's CloudFlare AAAA DynDNS"
    }
    $data = Invoke-WebRequest -Method Post -Uri "https://api.cloudflare.com/client/v4/zones/$($secrets.CLOUDFLARE_ZONE_ID)/dns_records" -Headers @{'Authorization' = "Bearer $($secrets.APIKEY)"} -Body ($myData | ConvertTo-Json) -Verbose:$false
    return ($data.Content | ConvertFrom-Json).result
}

function update_dns_post() {
    param(
        [Parameter(Mandatory)][PSObject]$secrets,
        [Parameter(Mandatory)][String]$id
    )
    $myData = @{
        "type"="AAAA"
        "name"=$secrets.HOSTNAME
        "content"=$secrets.IPv6
        "comment"="Added by Gnutt's CloudFlare AAAA DynDNS"
    }
    $data = Invoke-WebRequest -Method Patch -Uri "https://api.cloudflare.com/client/v4/zones/$($secrets.CLOUDFLARE_ZONE_ID)/dns_records/$($id)" -Headers @{'Authorization' = "Bearer $($secrets.APIKEY)"} -Body ($myData | ConvertTo-Json) -Verbose:$false
    return ($data.Content | ConvertFrom-Json).result
}

function remove_dns_post() {
    param(
        [Parameter(Mandatory)][PSObject]$secrets,
        [Parameter(Mandatory)][String]$id
    )

    $data = Invoke-WebRequest -Method Delete -Uri "https://api.cloudflare.com/client/v4/zones/$($secrets.CLOUDFLARE_ZONE_ID)/dns_records/$($id)" -Headers @{'Authorization' = "Bearer $($secrets.APIKEY)"} -Verbose:$false
    return ($data.Content | ConvertFrom-Json).result
}

function Get-ScriptDirectory
{
  $Invocation = (Get-Variable MyInvocation -Scope 1).Value
  Split-Path $Invocation.MyCommand.Path
}

if($Verbose) {
    $VerbosePreference = "Continue"
    Write-Verbose -Message "Enabling Verbose Output"
}

Write-Verbose -Message "Loading Secrets"
$secrets = Get-Content (Join-Path -Path (Get-ScriptDirectory) -ChildPath "secrets.json") | ConvertFrom-Json
$MANDATORY_SECRETS="HOSTNAME", "APIKEY", "CLOUDFLARE_ZONE_ID"

Write-Verbose -Message "Verifying all required secrets exists"
foreach($attr in $MANDATORY_SECRETS) {
    if(! (Get-Member -InputObject $secrets -Name $attr)) {
        Write-Error "Secrets is missing the property $attr"
        return -1
    }
}
Write-Verbose -Message "Asked internet what the public IPv6 Address is"
$PublicIPV6 = (Invoke-WebRequest -Uri "https://v6.ipinfo.io/ip" -Verbose:$false).Content 
Write-Verbose -Message "It was $($PublicIPV6), storing it in the global secrets variable"
$secrets | Add-Member -MemberType NoteProperty -Name 'IPv6' -Value $PublicIPV6

Write-Verbose -Message "Fetching all DNS posts"
$posts = fetch_all_dns -secrets $secrets
Write-Verbose -Message "Filtering posts for only matching name $($secrets.HOSTNAME) and type AAAA"
[Object[]]$filteredposts = $posts | Where-Object {$_.name -eq $secrets.HOSTNAME -and $_.type -eq "AAAA"}
Write-Verbose -Message "Still have $($filteredposts.Length) posts in the list"

if($filteredposts.Length -eq 0) {
    Write-Verbose -Message "Creating a new DNS post"
    create_dns_post -secrets $secrets
} elseif( $filteredposts.Length -gt 0) {
    Write-Verbose -Message "Checking that first DNS post returned has correct IPv6 address ($($filteredposts[0].content) compared to stored $($PublicIPV6))"
    if( $filteredposts[0].content -ne $secrets.IPv6 ) {
        Write-Verbose -Message "It did not, updating first DNS matching DNS post"
        update_dns_post -secrets $secrets -id $filteredposts[0].id
    }
}

if( $filteredposts.Length -gt 1) {
    Write-Verbose -Message "To many DNS posts found (should only have one), deleting superflous"
    $first,[Object[]]$rest = $filteredposts
    foreach($post in $rest) {
        remove_dns_post -secrets $secrets -id $post.id
    }
}