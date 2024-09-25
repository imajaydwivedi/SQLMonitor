<#
    Purpose: Run sql script on multiple servers, and process result
#>


[CmdletBinding()]
Param (
    [Parameter(Mandatory=$false)]
    [String]$InventoryServer = 'localhost',
    [Parameter(Mandatory=$false)]
    [String]$InventoryDatabase = 'DBA',
    [Parameter(Mandatory=$false)]
    [String]$CredentialManagerDatabase = 'DBA',
    [Parameter(Mandatory=$false)]
    [String]$AllServerLogin,
    [Parameter(Mandatory=$false)]
    [String]$WorkFolder = "C:\SQLMonitor\Work-Attachments",
    [Parameter(Mandatory=$false)]
    [bool]$RemoveLog = $true,
    [Parameter(Mandatory=$false)]
    [bool]$IgnorePingIssue = $false
)

$startTime = Get-Date
$startTimeString = Get-Date -Format yyyyMMMdd_HHmm

$verbose = $false;
if ($PSBoundParameters.ContainsKey('Verbose')) { # Command line specifies -Verbose[:$false]
    $verbose = $PSBoundParameters.Get_Item('Verbose')
}

$AppName = "Wrapper-GetHostIpAddresses.ps1"
$outputFile ="$WorkFolder\$AppName-$startTimeString.txt"

if (-not (Test-Path $outputFile)) {
    New-Item -Path $outputFile -Force -Confirm:$false | Out-Null
}

Set-DbatoolsConfig -FullName 'sql.connection.trustcert' -Value $true -Register

# Connect to Inventory Server, and get sa credential
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "[Connect-DbaInstance] Create connection for InventoryServer '$InventoryServer'.."
$conInventoryServer = Connect-DbaInstance -SqlInstance $InventoryServer -Database $InventoryDatabase -ClientName $AppName `
                                                    -TrustServerCertificate -EncryptConnection -ErrorAction Stop

# If AllServerLogin is provided, then fetch its credential from Credential manager
if ( -not [String]::IsNullOrEmpty($AllServerLogin) )
{
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Fetch [$AllServerLogin] password from Credential Manager [$InventoryServer].[$CredentialManagerDatabase].."
    $getCredential = @"
/* Fetch Credentials */
declare @password varchar(256);
exec dbo.usp_get_credential 
		@server_ip = '*',
		@user_name = @all_server_login,
		@password = @password output;
select @password as [password];
"@
    [string]$allServerLoginPassword = $conInventoryServer | Invoke-DbaQuery -Database $CredentialManagerDatabase `
                                -Query $getCredential -SqlParameter @{all_server_login = $AllServerLogin} | 
                                        Select-Object -ExpandProperty password -First 1

    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Create [$AllServerLogin] credential from fetched password.."
    [securestring]$secStringPassword = ConvertTo-SecureString $allServerLoginPassword -AsPlainText -Force
    [pscredential]$allServerLoginCredential = New-Object System.Management.Automation.PSCredential $AllServerLogin, $secStringPassword
}
else {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'WARNING:', "Since [`$AllServerLogin] is not provided, script would proceed with Windows Authentication."
}

# Get Hosts List without IPs
$qryGetHostsWithoutIPs = @"
select	[sql_instance] = h.server, id.sql_instance_port, [inventory_host_name] = h.host_name, 
		s.domain, s.hadr_strategy, [asi_host_name] = asi.host_name, [asi_machine_name] = asi.machine_name,
		[host_fqdn] = coalesce(h.host_name+'.'+asi.domain+'.com', h.host_name)
from dbo.sma_sql_server_hosts h
join dbo.sma_servers s
	on s.server = h.server
left join dbo.instance_details id 
	on id.sql_instance = s.server and id.host_name = h.host_name
	and id.is_enabled = 1 and id.is_alias = 0
left join dbo.vw_all_server_info asi
	on asi.srv_name = s.server
where s.is_decommissioned = 0 and h.is_decommissioned = 0
--and h.host_ips is null
"@
$hostsWithoutIPs = @()
$hostsWithoutIPs += $conInventoryServer | Invoke-DbaQuery -Database $InventoryDatabase -Query $qryGetHostsWithoutIPs

if($verbose) {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Following servers found-"
    $hostsWithoutIPs | ft -AutoSize
}

# Tsql script to execute
$findIPAddress = $true
if($findIPAddress)
{
    # Loop through servers list, and perform required action
    [System.Collections.ArrayList]$successServers = @()
    [System.Collections.ArrayList]$failedServers = @()
    [System.Collections.ArrayList]$queryResult = @()

    foreach($row in $hostsWithoutIPs)
    {
        $srvName = $row.sql_instance
        $srvPort = $row.sql_instance_port
        $host_name = $row.inventory_host_name
        $asi_host_name = $row.asi_host_name
        $asi_machine_name = $row.asi_machine_name
        $host_fqdn = $row.host_fqdn
        $domain = $row.domain
        $hadr_strategy = $row.hadr_strategy
        $host_ip1 = $null

        $srv = $srvName
        if (-not [String]::IsNullOrEmpty($srvPort)) {
            $srv = "$srvName,$srvPort"
        }

        "Working on [$srv].[$host_name].." | Tee-Object $outputFile -Append | Write-Host -ForegroundColor Cyan

        # Method 01: Ping Method
        try {
            $ip1 = Test-NetConnection $host_fqdn -ErrorAction Stop | Select-Object -ExpandProperty RemoteAddress
        }
        catch {
            $errMsg = $_.Exception.Message
            $failedServers.Add([PSCustomObject]@{sql_instance = $srv; host_name = $host_name; method = 'Test-NetConnection'; error = $errMsg}) | Out-Null
            "`n`tError: $errMsg" | Write-Host -ForegroundColor Red
        }
        
        if ([String]::IsNullOrEmpty($ip1)) {
            try {
                $ip1 = Test-Connection $host_fqdn -Count 1 -ErrorAction Stop | Select-Object -ExpandProperty IPV4Address
            }
            catch {
                $errMsg = $_.Exception.Message
                $failedServers.Add([PSCustomObject]@{sql_instance = $srv; host_name = $host_name; method = 'Test-Connection'; error = $errMsg}) | Out-Null
                "`n`tError: $errMsg" | Write-Host -ForegroundColor Red
            }
        }

        if ( $IgnorePingIssue -or (-not [String]::IsNullOrEmpty($ip1)) ) {
            $db_row = [PSCustomObject]@{
                            sql_instance = $srvName; 
                            sql_instance_port = $srvPort; 
                            host_name = $host_name; 
                            Ip = $ip1; 
                            hadr_strategy = $hadr_strategy;
                            host_fqdn = $host_fqdn;
                            collection_time = $startTime
                        }

            $queryResult.Add($db_row) | Out-Null

            if (-not [String]::IsNullOrEmpty($ip1)) {
                $successServers.Add([PSCustomObject]@{sql_instance=$srvName; host_name = $host_name}) | Out-Null
            }
            continue
        }
    }

    if($verbose) {
        $failedServers | ogv
        $queryResult | ogv
    }

    "`Result => `n" | Out-File $outputFile -Append
    $queryResult  | Format-Table -AutoSize | Out-File $outputFile -Append

    "`Successful Servers => `n" | Out-File $outputFile -Append
    $successServers | Format-Table -AutoSize | Out-File $outputFile -Append

    "`nFailed Servers => `n" | Out-File $outputFile -Append
    $failedServers | Format-Table -AutoSize | Out-File $outputFile -Append

    $queryResult | Write-DbaDbTableData -SqlInstance $conInventoryServer -Database $InventoryDatabase -Table 'sma_sql_server_hosts_wrapper' -Truncate -AutoCreateTable
}

if($RemoveLog) {
    Remove-Item $outputFile -Confirm:$false
}