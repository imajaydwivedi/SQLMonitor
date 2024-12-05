[CmdletBinding()]
Param (
  [Parameter(Mandatory = $false)]
  [String]$InventoryServer = 'OfficeInventory',
  [Parameter(Mandatory = $false)]
  [String]$InventoryDatabase = 'DBA',
  [Parameter(Mandatory = $false)]
  [String]$CredentialManagerDatabase = 'DBA_Inventory',
  [Parameter(Mandatory = $True)]
  [PSCredential]$AllServerLoginCredential,
  [Parameter(Mandatory=$false)]
  [String]$ClientName = "Wrapper-AllServersUpdateRetention.ps1"
)

<# Purpose:  Loop through all SQLMonitor servers, and execute sql query #>


"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "[Connect-DbaInstance] Create connection for InventoryServer '$InventoryServer'.."
$conInventoryServer = Connect-DbaInstance -SqlInstance $InventoryServer -Database $InventoryDatabase -ClientName "Wrapper-UpdateSQLAgentJobsThreshold.ps1" `
  -TrustServerCertificate -EncryptConnection -ErrorAction Stop -SqlCredential $AllServerLoginCredential


# Get SQLMonitor servers
$sqlGetServers = @"
select  distinct 
        id.sql_instance, id.[database], id.sql_instance_port, 
        sql_instance_with_port = coalesce(id.sql_instance +','+ id.sql_instance_port, id.sql_instance)
from dbo.instance_details id
where id.is_enabled = 1
and id.is_available = 1
and id.is_alias = 0
"@

$servers = @()
$servers += $conInventoryServer | Invoke-DbaQuery -Database $InventoryDatabase -Query $sqlGetServers | Select-Object -Property sql_instance, sql_instance_port, sql_instance_with_port, database -Unique

#$fileWithDDLs = 'D:\GitHub-Personal\SQLMonitor\DDLs\SCH-usp_avg_disk_wait_ms.sql'

$preSQL = @"
update pt
set retention_days = 365*3
from dbo.purge_table pt
where pt.table_name in ('dbo.file_io_stats');

select sql_instance = @sql_instance, action_taken = 'Updated retention';
"@


# Loop through servers list, and perform required action
[System.Collections.ArrayList]$queryResult = @()
[System.Collections.ArrayList]$successServers = @()
[System.Collections.ArrayList]$failedServers = @()

#$serversRemaining = $servers | ? {$_ -notin $successServers }
#$successServersFinal = $successServers

foreach ($srvDtls in $servers) {
  $srv = $srvDtls.sql_instance_with_port
  $sqlInstance = $srvDtls.sql_instance
  $sqlInstanceWithPort = $srvDtls.sql_instance_with_port
  $sqlInstancePort = $srvDtls.sql_instance_port  
  $database = $srvDtls.database
  $actionRequired4SqlInstance = $true

  "Working on [$sqlInstance].." | Write-Host -ForegroundColor Cyan
  try {
    $srvObj = Connect-DbaInstance -SqlInstance $sqlInstanceWithPort -Database $database -ClientName "Wrapper-AllServersUpdateRetention.ps1" `
                -SqlCredential $allServerLoginCredential -TrustServerCertificate -EncryptConnection -ErrorAction Stop

    # Execute pre sql & save result in $queryResult
    $srvObj | Invoke-DbaQuery -Query $preSQL -SqlParameter @{sql_instance = $sqlInstance} -EnableException | ForEach-Object { $queryResult.Add($_) | Out-Null}

    #$sqlGrafanaLogin = [System.IO.File]::ReadAllText($grafanaPermissionsFile).Replace("[DBA]", "[$database]")

    #$actionRequired4SqlInstance = $queryResult | ? {$_.sql_instance -eq $sqlInstance} | Select -ExpandProperty action_taken -First 1

    # Update threshold using file script
    #if ($actionRequired4SqlInstance) {
    #$srvObj | Invoke-DbaQuery -File $fileWithDDLs -EnableException
    #$srvObj | Invoke-DbaQuery -Query $sqlGrafanaLogin
    #}

    $successServers.Add([PSCustomObject]@{server = $sqlInstance; server_with_port = $sqlInstanceWithPort; action_taken = $actionRequired4SqlInstance }) | Out-Null
  }
  catch {
    $errMsg = $_.Exception.Message
    $failedServers.Add([PSCustomObject]@{server = $sqlInstance; server_with_port = $sqlInstanceWithPort; error = $errMsg }) | Out-Null
    "`n`tError: $errMsg" | Write-Host -ForegroundColor Red
  }
}

$successServers | Out-ConsoleGridView -Title "Successful"
$failedServers | Out-ConsoleGridView -Title "Failed"
$serversNotConsidered | Out-ConsoleGridView -Title "Not Considered Servers"

<#
# Install-Module -Name Microsoft.PowerShell.ConsoleGuiTools
# Install-Module -Name dbatools -Scope AllUsers

$AllServerLogin = "sa"
$AllServerLoginPassword = Read-Host -Prompt 'Enter a Password' -AsSecureString
$AllServerLoginCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $AllServerLogin, $AllServerLoginPassword

~/Documents/Github/SQLMonitor/Work-SQLMonitor-Deployments/Wrapper-All-Servers-Update-Retention-PWSH.ps1 `
              -AllServerLoginCredential $AllServerLoginCredential
#>