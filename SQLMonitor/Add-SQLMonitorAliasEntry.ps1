[CmdletBinding()]
Param (
    [Parameter(Mandatory=$true)]
    [String]$AliasSqlInstance,
    [Parameter(Mandatory=$false)]
    [String]$SourceSqlInstance,
    [Parameter(Mandatory=$true)]
    [String]$InventoryServer,
    [Parameter(Mandatory=$false)]
    [String]$InventoryDatabase = 'DBA',
    [Parameter(Mandatory=$false)]
    [PSCredential]$SqlCredential,
    [Parameter(Mandatory=$false)]
    [bool]$DropCreateLinkedServer = $false,
    [Parameter(Mandatory=$false)]
    [bool]$ReturnInlineErrorMessage = $false,
    [Parameter(Mandatory=$false)]
    [bool]$Move2NextStepOnFailure = $false
)

$startTime = Get-Date
$ErrorActionPreference = "Stop"

$verbose = $false;
if ($PSBoundParameters.ContainsKey('Verbose')) { # Command line specifies -Verbose[:$false]
    $verbose = $PSBoundParameters.Get_Item('Verbose')
}

$debug = $false;
if ($PSBoundParameters.ContainsKey('Debug')) { # Command line specifies -Debug[:$false]
    $debug = $PSBoundParameters.Get_Item('Debug')
}

[String]$LinkedServerOnInventoryFileName = "SCH-Linked-Servers-Sample.sql"

# Check if PortNo is specified
$Port4AliasSqlInstance = $null
$AliasSqlInstanceWithOutPort = $AliasSqlInstance
if($AliasSqlInstance -match "(?'SqlInstance'.+),(?'PortNo'\d+)") {
    $Port4AliasSqlInstance = $Matches['PortNo']
    $AliasSqlInstanceWithOutPort = $Matches['SqlInstance']
}

$Port4SourceSqlInstance = $null
$SourceSqlInstanceWithOutPort = $SourceSqlInstance
if($SourceSqlInstance -match "(?'SqlInstance'.+),(?'PortNo'\d+)") {
    $Port4SourceSqlInstance = $Matches['PortNo']
    $SourceSqlInstanceWithOutPort = $Matches['SqlInstance']
}

$Port4InventoryServer = $null
$InventoryServerWithOutPort = $InventoryServer
if($AliasSqlInstance -ne $InventoryServer) {
    if($InventoryServer -match "(?'SqlInstance'.+),(?'PortNo'\d+)") {
        $Port4InventoryServer = $Matches['PortNo']
        $InventoryServerWithOutPort = $Matches['SqlInstance']
    }
} else {
    $Port4InventoryServer = $Port4AliasSqlInstance
}

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'START:', "Working on server [$AliasSqlInstance]." | Write-Host -ForegroundColor Yellow
if(-not [String]::IsNullOrEmpty($Port4AliasSqlInstance)) {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "SQL Port for [$AliasSqlInstance] => $Port4AliasSqlInstance." | Write-Host -ForegroundColor Yellow
}

# Evaluate path of SQLMonitor folder
if( (-not [String]::IsNullOrEmpty($PSScriptRoot)) -or ((-not [String]::IsNullOrEmpty($SQLMonitorPath)) -and $(Test-Path $SQLMonitorPath)) ) {
    if([String]::IsNullOrEmpty($SQLMonitorPath)) {
        $SQLMonitorPath = $(Split-Path $PSScriptRoot -Parent)
    }
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "`$SQLMonitorPath = '$SQLMonitorPath'"
}
else {
    if ($ReturnInlineErrorMessage) {
		"Kindly provide 'SQLMonitorPath' parameter value" | Write-Error
	}
	else {            
		"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'ERROR:', "Kindly provide 'SQLMonitorPath' parameter value" | Write-Host -ForegroundColor Red
        if(-not $Move2NextStepOnFailure) {
            Write-Error "Stop here. Fix above issue."
        }
    }
}

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "`$AliasSqlInstance = [$AliasSqlInstance]"
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "`$SqlCredential => "
$SqlCredential | ft -AutoSize

# Construct File Path Variables
$ddlPath = Join-Path $SQLMonitorPath "DDLs"
$psScriptPath = Join-Path $SQLMonitorPath "SQLMonitor"
$isUpgradeScenario = $false

$LinkedServerOnInventoryFilePath = "$ddlPath\$LinkedServerOnInventoryFileName"

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "`$ddlPath = '$ddlPath'"
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "`$psScriptPath = '$psScriptPath'"

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Import dbatools module.."
Import-Module dbatools


# Setup SQL Connection for Inventory
try {
    #if($InventoryServer -ne $AliasSqlInstance) {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "[Connect-DbaInstance] Create connection for InventoryServer '$InventoryServer'.."
    $conInventoryServer = Connect-DbaInstance -SqlInstance $InventoryServer -Database master -ClientName "Wrapper-InstallSQLMonitor.ps1" `
                                                    -SqlCredential $SqlCredential -TrustServerCertificate -EncryptConnection -ErrorAction Stop
    #} else {
        #$conInventoryServer = $conAliasSqlInstance
    #}
}
catch {
    $errMessage = "Connect-DbaInstance => $($_.Exception.Message)"
    
    if ($ReturnInlineErrorMessage) 
    {
        if([String]::IsNullOrEmpty($SqlCredential)) {
            $errMessage = "SQL Connection to [$InventoryServer] failed.`nKindly provide SqlCredentials.`n$errMessage.."
        } else {
            $errMessage = "SQL Connection to [$InventoryServer] failed.`nProvided SqlCredentials seems to be NOT working.`n$errMessage.."
        }
        
        $errMessage | Write-Error
    }
    else
    {
        "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'ERROR:', "SQL Connection to [$InventoryServer] failed." | Write-Host -ForegroundColor Red
        "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'ERROR:', "$errMessage." | Write-Host -ForegroundColor Red
        if([String]::IsNullOrEmpty($SqlCredential)) {
            "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'ERROR:', "Kindly provide SqlCredentials." | Write-Host -ForegroundColor Red
        } else {
            "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'ERROR:', "Provided SqlCredentials seems to be NOT working." | Write-Host -ForegroundColor Red
        }

        if(-not $Move2NextStepOnFailure) {
            Write-Error "Stop here. Fix above issue."
        }
    }
}

# Fetch details regarding AliasSqlInstance
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Fetch details regarding AliasSqlInstance [$AliasSqlInstance].."
$sqlGetSourceServers = @"
--declare @alias_sql_instance varchar(255);
--declare @source_sql_instance varchar(255);
--set @alias_sql_instance = '192.168.1.11';
--set @source_sql_instance = '192.168.1.10';

select s.server, ag.ag_listener_name, ag.ag_listener_ip1, ag.ag_listener_ip2,
        alias_sql_instance = @alias_sql_instance,
        source_sql_instance = @source_sql_instance
from dbo.sma_servers s
join dbo.sma_hadr_ag ag
	on ag.server = s.server
where s.is_decommissioned = 0
and ag.is_decommissioned = 0
and s.hadr_strategy = 'ag'
and (	( ag.ag_listener_ip1 is not null and ag.ag_listener_ip1 = @alias_sql_instance )
	or	( ag.ag_listener_ip2 is not null and ag.ag_listener_ip2 = @alias_sql_instance )
    or	(ag.ag_listener_name is not null and ag.ag_listener_name = @alias_sql_instance )
	)
$(if([String]::IsNullOrEmpty($SourceSqlInstance)){'--'})and s.server = @source_sql_instance;
"@

[System.Collections.Arraylist]$resultSourceServers = @()
try {
    $sqlParams = @{
            alias_sql_instance = $AliasSqlInstanceWithOutPort; 
            source_sql_instance = $SourceSqlInstanceWithOutPort
    }
    $conInventoryServer | Invoke-DbaQuery -Database $InventoryDatabase -Query $sqlGetSourceServers -SqlParameter $sqlParams -EnableException `
        | ForEach-Object {$resultSourceServers.Add($_) | Out-Null}
    $resultSourceServers | Format-Table -AutoSize
}
catch {
    $errMessage = $_.Exception.Message
    
    if ($ReturnInlineErrorMessage) 
    {
        if([String]::IsNullOrEmpty($SqlCredential)) {
            $errMessage = "SQL Connection to [$InventoryServer] failed.`nKindly provide SqlCredentials.`n$errMessage.."
        } else {
            $errMessage = "SQL Connection to [$InventoryServer] failed.`nProvided SqlCredentials seems to be NOT working.`n$($errMessage.Exception.Message).."
        }

        $errMessage | Write-Error
    }
    else
    {
        "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'ERROR:', "SQL Connection to [$InventoryServer] failed.`n$errMessage"
        if([String]::IsNullOrEmpty($SqlCredential)) {
            "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'ERROR:', "Kindly provide SqlCredentials." | Write-Host -ForegroundColor Red
        } else {
            "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'ERROR:', "Provided SqlCredentials seems to be NOT working." | Write-Host -ForegroundColor Red
        }
        if(-not $Move2NextStepOnFailure) {
            Write-Error "Stop here. Fix above issue."
        }
    }
}

if($resultSourceServers.Count -eq 0) {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'ERROR:', "No details of source SQLInstances found in inventory tables."
    if(-not $Move2NextStepOnFailure) {
        Write-Error "Stop here. Fix above issue."
    }
}


# Fetch details of Source SQL Instances from dbo.instance_details
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Fetch details of Source SQL Instances from dbo.instance_details.."
$sqlServersCSV = ($resultSourceServers.server | % {"'$_'"}) -join ','
[System.Collections.Arraylist]$resultSourceSQLInstances = @()

$sqlGetSourceInstances = @"
select *
from dbo.instance_details id
where id.is_enabled = 1
and id.is_alias = 0
and id.sql_instance in ($sqlServersCSV)
"@

try {
    $conInventoryServer | Invoke-DbaQuery -Database $InventoryDatabase -Query $sqlGetSourceInstances -EnableException `
        | ForEach-Object {$resultSourceSQLInstances.Add($_) | Out-Null}
    $resultSourceSQLInstances | Format-Table -AutoSize
}
catch {
    $errMessage = $_.Exception.Message
    
    if ($ReturnInlineErrorMessage) 
    {
        if([String]::IsNullOrEmpty($SqlCredential)) {
            $errMessage = "SQL Connection to [$InventoryServer] failed.`nKindly provide SqlCredentials.`n$errMessage.."
        } else {
            $errMessage = "SQL Connection to [$InventoryServer] failed.`nProvided SqlCredentials seems to be NOT working.`n$($errMessage.Exception.Message).."
        }

        $errMessage | Write-Error
    }
    else
    {
        "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'ERROR:', "SQL Connection to [$InventoryServer] failed.`n$errMessage"
        if([String]::IsNullOrEmpty($SqlCredential)) {
            "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'ERROR:', "Kindly provide SqlCredentials." | Write-Host -ForegroundColor Red
        } else {
            "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'ERROR:', "Provided SqlCredentials seems to be NOT working." | Write-Host -ForegroundColor Red
        }
        if(-not $Move2NextStepOnFailure) {
            Write-Error "Stop here. Fix above issue."
        }
    }
}

Write-Debug "Fetch next info"

if($resultSourceSQLInstances.Count -eq 0) {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'ERROR:', "No details of source SQLInstances found in dbo.instance_details table."
    if(-not $Move2NextStepOnFailure) {
        Write-Error "Stop here. Fix above issue."
    }
}

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Loop through each source sql instance, and populate an Alias entry.."
[System.Collections.Arraylist]$resultAliasSqlEntries = @()
[System.Collections.Arraylist]$failedAliasEntries = @()
foreach($row in $resultSourceSQLInstances) {
    $sqlParams = [ordered]@{
        sql_instance = $AliasSqlInstanceWithOutPort;
        host_name = $row.host_name;
        database = $row.database;
        collector_tsql_jobs_server = $row.collector_tsql_jobs_server;
        collector_powershell_jobs_server = $row.collector_powershell_jobs_server;
        data_destination_sql_instance = $row.data_destination_sql_instance;
        is_available = $row.is_available;
        created_date_utc = $row.created_date_utc;
        last_unavailability_time_utc = $row.last_unavailability_time_utc;
        dba_group_mail_id = $row.dba_group_mail_id;
        sqlmonitor_script_path = $row.sqlmonitor_script_path;
        sqlmonitor_version = $row.sqlmonitor_version;
        is_alias = 1;
        source_sql_instance = $row.sql_instance;
        sql_instance_port = $row.sql_instance_port;
        more_info = $row.more_info;
        is_enabled = $row.is_enabled;
        is_linked_server_working = $row.is_linked_server_working;
    }

    $sqlInsertAliasEntry = @"
declare @is_inserted bit = 0;
if not exists (select * from dbo.instance_details where is_enabled = 1 and sql_instance = @sql_instance and source_sql_instance = @source_sql_instance and host_name = @host_name)
begin
    insert dbo.instance_details
    ([sql_instance], [host_name], [database], [collector_tsql_jobs_server], [collector_powershell_jobs_server], [data_destination_sql_instance], [is_available], [created_date_utc], [last_unavailability_time_utc], [dba_group_mail_id], [sqlmonitor_script_path], [sqlmonitor_version], [is_alias], [source_sql_instance], [sql_instance_port], [more_info], [is_enabled], [is_linked_server_working])
    select @sql_instance, @host_name, @database, @collector_tsql_jobs_server, @collector_powershell_jobs_server, @data_destination_sql_instance, @is_available, @created_date_utc, @last_unavailability_time_utc, @dba_group_mail_id, @sqlmonitor_script_path, @sqlmonitor_version, @is_alias, @source_sql_instance, @sql_instance_port, @more_info, @is_enabled, @is_linked_server_working;

    set @is_inserted = 1;
end

select [is_inserted] = @is_inserted, *
from dbo.instance_details id
where id.is_enabled = 1
and id.sql_instance = @sql_instance
and id.source_sql_instance = @source_sql_instance
and host_name = @host_name;
"@
    
    try {
        $conInventoryServer | Invoke-DbaQuery -Database $InventoryDatabase -Query $sqlInsertAliasEntry -SqlParameter $sqlParams -EnableException `
            | ForEach-Object {$resultAliasSqlEntries.Add($_) | Out-Null}
    }
    catch {
        $errMessage = $_.Exception.Message
        $failedAliasEntries.Add([PSCustomObject]$sqlParams) | Out-Null
    
        if ($ReturnInlineErrorMessage) 
        {
            $errMessage = "Insert into dbo.instance_details failed.`n`n$errMessage.."
            #$errMessage | Write-Error
        }
        else
        {
            "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'ERROR:', "Insert into dbo.instance_details failed." | Write-Host -ForegroundColor Red
            "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'ERROR:', "$errMessage" | Write-Host -ForegroundColor Red
            if(-not $Move2NextStepOnFailure) {
                Write-Error "Stop here. Fix above issue."
            }
        }
    }

}


"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "`$LinkedServerOnInventoryFilePath = '$LinkedServerOnInventoryFilePath'"
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Creating linked server for [$AliasSqlInstance] on [$InventoryServer].."
$sqlLinkedServerOnInventory = [System.IO.File]::ReadAllText($LinkedServerOnInventoryFilePath)
$DbaDatabase = $resultSourceSQLInstances[0].database
$AliasInstancePort = $resultSourceSQLInstances[0].sql_instance_port
$AliasSqlInstanceWithPort = $AliasSqlInstance
if(-not [String]::IsNullOrEmpty($AliasInstancePort)) {
    $AliasSqlInstanceWithPort = "$AliasSqlInstance,$AliasInstancePort"
}
$sqlLinkedServerOnInventory = $sqlLinkedServerOnInventory.Replace("@server = N'YourSqlInstanceNameHere'", "@server = N'$AliasSqlInstanceWithOutPort'")
$sqlLinkedServerOnInventory = $sqlLinkedServerOnInventory.Replace("@server=N'YourSqlInstanceNameHere'", "@server=N'$AliasSqlInstanceWithOutPort'")
$sqlLinkedServerOnInventory = $sqlLinkedServerOnInventory.Replace("@rmtsrvname=N'YourSqlInstanceNameHere'", "@rmtsrvname=N'$AliasSqlInstanceWithOutPort'")
$sqlLinkedServerOnInventory = $sqlLinkedServerOnInventory.Replace("@datasrc=N'YourSqlInstanceNameHere'", "@datasrc=N'$AliasSqlInstanceWithPort'")
$sqlLinkedServerOnInventory = $sqlLinkedServerOnInventory.Replace("@catalog=N'DBA'", "@catalog=N'$DbaDatabase'")
    
$dbaLinkedServer = @()
$dbaLinkedServer += Get-DbaLinkedServer -SqlInstance $conInventoryServer -LinkedServer $AliasSqlInstanceWithOutPort
if($dbaLinkedServer.Count -eq 0) {
    $conInventoryServer | Invoke-DbaQuery -Database master -Query $sqlLinkedServerOnInventory -EnableException
} else {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Linked server for [$AliasSqlInstance] on [$InventoryServer] already exists.."
}

"*"*80
"`n$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Insert query result.."
$resultAliasSqlEntries | Format-Table -AutoSize
"*"*80

"*"*80
if($failedAliasEntries.Count -gt 0) {
    "`n$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Failed entries.."
    $failedAliasEntries | Format-Table -AutoSize
    $failedAliasEntries | ogv

    $sourceInstancesCSV = ($failedAliasEntries.source_sql_instance | % {"'$_'"}) -join ','
    $sourceHostsCSV = ($failedAliasEntries.host_name | % {"'$_'"}) -join ','

    $sqlToRemoveAliasEntry = @"
select *
-- delete id 
from dbo.instance_details id
where 1=1
--and id.is_enabled = 1
and id.sql_instance in ('$AliasSqlInstanceWithOutPort')
and id.source_sql_instance in ($sourceInstancesCSV)
and id.host_name in ($sourceHostsCSV)
and id.is_alias = 1
"@
    
    "`n`n$sqlToRemoveAliasEntry`n`n" | Write-Host -ForegroundColor Cyan
}
else {
    "`n$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "No Failed entries.."
}
"*"*80
