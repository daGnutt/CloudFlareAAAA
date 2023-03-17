function fetch_all_dns() {
    param(
        [Parameter(Mandatory)][PSCustomObject]$secrets
    )
    $data = Invoke-WebRequest -Method Get -Uri "https://api.cloudflare.com/client/v4/zones/$($secrets.CLOUDFLARE_ZONE_ID)/dns_records" -Headers @{'Authorization' = "Bearer $($secrets.APIKEY)"}
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
    }
    $data = Invoke-WebRequest -Method Post -Uri "https://api.cloudflare.com/client/v4/zones/$($secrets.CLOUDFLARE_ZONE_ID)/dns_records" -Headers @{'Authorization' = "Bearer $($secrets.APIKEY)"} -Body ($myData | ConvertTo-Json)
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
    }
    $data = Invoke-WebRequest -Method Patch -Uri "https://api.cloudflare.com/client/v4/zones/$($secrets.CLOUDFLARE_ZONE_ID)/dns_records/$($id)" -Headers @{'Authorization' = "Bearer $($secrets.APIKEY)"} -Body ($myData | ConvertTo-Json)
    return ($data.Content | ConvertFrom-Json).result
}

function remove_dns_post() {
    param(
        [Parameter(Mandatory)][PSObject]$secrets,
        [Parameter(Mandatory)][String]$id
    )

    $data = Invoke-WebRequest -Method Delete -Uri "https://api.cloudflare.com/client/v4/zones/$($secrets.CLOUDFLARE_ZONE_ID)/dns_records/$($id)" -Headers @{'Authorization' = "Bearer $($secrets.APIKEY)"}
    return ($data.Content | ConvertFrom-Json).result
}

function Get-ScriptDirectory
{
  $Invocation = (Get-Variable MyInvocation -Scope 1).Value
  Split-Path $Invocation.MyCommand.Path
}

$secrets = Get-Content (Join-Path -Path (Get-ScriptDirectory) -ChildPath "secrets.json") | ConvertFrom-Json
$MANDATORY_SECRETS="HOSTNAME", "APIKEY", "CLOUDFLARE_ZONE_ID"

foreach($attr in $MANDATORY_SECRETS) {
    if(! (Get-Member -InputObject $secrets -Name $attr)) {
        Write-Error "Secrets is missing the property $attr"
        return -1
    }
}
$PublicIPV6 = (Invoke-WebRequest -Uri "https://v6.ipinfo.io/ip").Content
$secrets | Add-Member -MemberType NoteProperty -Name 'IPv6' -Value $PublicIPV6

$posts = fetch_all_dns -secrets $secrets
[Object[]]$filteredposts = $posts | Where-Object {$_.name -eq $secrets.HOSTNAME -and $_.type -eq "AAAA"}

if($filteredposts.Length -eq 0) {
    create_dns_post -secrets $secrets
} elseif( $filteredposts.Length -gt 0) {
    if( $filteredposts[0].content -ne $secrets.IPv6 ) {
        update_dns_post -secrets $secrets -id $filteredposts[0].id
    }
}

if( $filteredposts.Length -gt 1) {
    $first,[Object[]]$rest = $filteredposts
    foreach($post in $rest) {
        remove_dns_post -secrets $secrets -id $post.id
    }
}