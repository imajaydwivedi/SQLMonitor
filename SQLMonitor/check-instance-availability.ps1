[CmdletBinding()]
Param (
    # Set SQL Server where data should be saved
    [Parameter(Mandatory=$false)]
    $InventoryServer = 'localhost',
    [Parameter(Mandatory=$false)]
    $InventoryDatabase = 'DBA',
    [Parameter(Mandatory=$false)]
    $Threads = 4,
    [Parameter(Mandatory=$false)]
    [bool]$SkipNotOnBoardedServers = $false,
    [Parameter(Mandatory=$false)]
    [String]$ClientAppName = "check-instance-availability.ps1",
    [Parameter(Mandatory=$false)]
    [String]$JobName = "(dba) Check-InstanceAvailability"
)

$modulePath = [Environment]::GetEnvironmentVariable('PSModulePath')
$modulePath += ';C:\Program Files\WindowsPowerShell\Modules'
[Environment]::SetEnvironmentVariable('PSModulePath', $modulePath)

Import-Module dbatools
Import-Module PoshRSJob -WarningAction Continue;

$ErrorActionPreference = 'Stop'
$currentTime = Get-Date
$ClientAppName = "check-instance-availability.ps1"

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "[Connect-DbaInstance] Create connection for '$InventoryServer'.."
$conInventoryServer = Connect-DbaInstance -SqlInstance $InventoryServer -Database master -ClientName $ClientAppName -TrustServerCertificate -EncryptConnection

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Get all SQLInstances in SQLMonitor server [$InventoryServer].[dbo].[instance_details].."
$sqlSupportedInstances = @"
select distinct [sql_instance], [sql_instance_port], [database] 
from dbo.instance_details id
outer apply (select s.is_onboarded from dbo.sma_servers s 
			where s.is_decommissioned = 0 and s.server = id.sql_instance
			) s
where is_enabled = 1 and is_alias = 0
and id.host_name <> CONVERT(varchar,COALESCE(SERVERPROPERTY('ComputerNamePhysicalNetBIOS'),SERVERPROPERTY('ServerName')))
and (s.is_onboarded = 1 or s.is_onboarded is null)
"@ 
$supportedInstances = @()
$supportedInstances += $conInventoryServer | Invoke-DbaQuery -Database $InventoryDatabase -Query $sqlSupportedInstances -EnableException

if($supportedInstances.Count -gt 0) {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Below SQLInstances found in dbo.instance_details-"
    "`n($(($supportedInstances.sql_instance|%{"'$_'"}) -join ','))`n"

    # Create Grafana Credential
    $username = "grafana"
    $password = ConvertTo-SecureString "grafana" -AsPlainText -Force
    $sqlCredential = New-Object System.Management.Automation.PSCredential -ArgumentList ($username, $password)

    $sqlAddErrorLogEntry = @"
insert dbo.sma_errorlog
(function_name, function_call_arguments, server, error, executor_program_name)
select @function_name, @function_call_arguments, @server, @error, @executor_program_name
"@

    # Loop through each SQLInstance
    $blockGetServerHealth = {
        $sqlInstanceDetails = $_;
        $sqlInstance = $sqlInstanceDetails.sql_instance
        if([String]::IsNullOrEmpty($sqlInstanceDetails.sql_instance_port)) {
            $sqlInstanceWithPort = $sqlInstance
        } else {
            $sqlInstanceWithPort = "$sqlInstance,$($sqlInstanceDetails.sql_instance_port)"
        }
        $dbaDatabase = $sqlInstanceDetails.database
    
        #"`$sqlInstance => $sqlInstance"

        Import-Module dbatools
        $conSqlInstanceWithPort = Connect-DbaInstance -SqlInstance $sqlInstanceWithPort -Database master -ClientName $ClientAppName -SqlCredential $Using:sqlCredential -TrustServerCertificate -EncryptConnection
        $conSqlInstanceWithPort | Invoke-DbaQuery -Database $database -Query "select [sql_instance] = '$sqlInstance', [database] = db_name();" -EnableException;
    }

    "{0} {1,-10} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))","(INFO)","Start RSJobs with $Threads threads.." | Write-Output
    $jobs = @()
    $jobs += $supportedInstances | Start-RSJob -Name {"$($_.sql_instance)"} -ScriptBlock $blockGetServerHealth -Throttle $Threads
    "{0} {1,-10} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))","(INFO)","Waiting for RSJobs to complete.." | Write-Verbose
    $jobs | Wait-RSJob -ShowProgress -Timeout 1200 -Verbose:$false | Out-Null

    $jobs_timedout = @()
    $jobs_timedout += $jobs | Where-Object {$_.State -in ('NotStarted','Running','Stopping')}
    $jobs_success = @()
    $jobs_success += $jobs | Where-Object {$_.State -eq 'Completed' -and $_.HasErrors -eq $false}
    $jobs_fail = @()
    $jobs_fail += $jobs | Where-Object {$_.HasErrors -or $_.State -in @('Disconnected')}

    $jobsResult = @()
    $jobsResult += $jobs_success | Receive-RSJob -Verbose:$false
    
    if($jobs_success.Count -gt 0) {
        "{0} {1,-10} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))","(INFO)","Below jobs finished without error.." | Write-Output
        $jobs_success | Select-Object Name, State, HasErrors | Format-Table -AutoSize | Out-String | Write-Output
    }

    if($jobs_timedout.Count -gt 0)
    {
        "{0} {1,-10} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))","(ERROR)","Some jobs timed out. Could not completed in 20 minutes." | Write-Output
        $jobs_timedout | Format-Table -AutoSize | Out-String | Write-Output
        "{0} {1,-10} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))","(INFO)","Stop timedout jobs.." | Write-Output
        $jobs_timedout | Stop-RSJob
    }

    if($jobs_fail.Count -gt 0)
    {
        "{0} {1,-10} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))","(ERROR)","Some jobs failed." | Write-Output
        $jobs_fail | Format-Table -AutoSize | Out-String | Write-Output
        "--"*20 | Write-Output
    }

    $jobs_exception = @()
    $jobs_exception += $jobs_timedout + $jobs_fail
    [System.Collections.ArrayList]$jobErrMessages = @()
    if($jobs_exception.Count -gt 0 ) {   
        $alertHost = $jobs_exception | Select-Object -ExpandProperty Name -First 1
        $isCustomError = $true
        $errMessage = "`nBelow jobs either timed or failed-`n$($jobs_exception | Select-Object Name, State, HasErrors | Format-Table -AutoSize | Out-String -Width 700)"
        $failCount = $jobs_fail.Count
        $failCounter = 0
        foreach($job in $jobs_fail) {
            $failCounter += 1
            $jobErrMessage = ''
            if($failCounter -eq 1) {
                $jobErrMessage = "`n$("_"*20)`n" | Write-Output
            }
            $jobErrMessage += "`nError Message for server [$($job.Name)] => `n`n$($job.Error | Out-String)"
            $jobErrMessage += "$("_"*20)`n`n" | Write-Output
            $jobErrMessages.Add($jobErrMessage) | Out-Null;

            Write-Debug "Inside failed job loop"

            $exceptionMessage = $job.Error.Exception.Message
            $garbageText = 'Exception calling "EndInvoke" with "1" argument(s): '
            $errorParams = [ordered]@{
                function_name = $ClientAppName
                function_call_arguments = 'Failed-Jobs'
                server = $job.Name
                error = $exceptionMessage.Replace($garbageText,'')
                executor_program_name = $JobName
            }
            "{0} {1,-10} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))","(INFO)","Marking an entry in error log table dbo.sma_errorlog.." | Write-Output
            $conInventoryServer | Invoke-DbaQuery -Database $InventoryDatabase -Query $sqlAddErrorLogEntry `
                        -EnableException -ErrorAction Stop -SqlParameter $errorParams
        
        }
        $errMessage += ($jobErrMessages -join '')
        #throw $errMessage

        foreach($job in $jobs_timedout) {
            #$exceptionMessage = $job.Error.Exception.Message
            #$garbageText = 'Exception calling "EndInvoke" with "1" argument(s): '
            $errorParams = @{
                function_name = $ClientAppName
                function_call_arguments = 'TimedOut-Jobs'
                server = $job.Name
                error = 'Query Timed Out'
                executor_program_name = $JobName
            }
            $conInventoryServer | Invoke-DbaQuery -Database $InventoryDatabase -Query $sqlAddErrorLogEntry `
                        -EnableException -ErrorAction Stop -SqlParameter $errorParams
        }
    }
    $jobs | Remove-RSJob -Verbose:$false

    #throw $errMessage

    if($jobsResult.Count -gt 0) {
        "{0} {1,-10} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))","(INFO)","Setting [is_available] flag for $($jobsResult.Count) online server(s).."
        $onlineSqlInstancesCSV = (($jobsResult.sql_instance | % {"'$_'"}) -join ',')
        $sqlSetOnlineFlag = @"
    update dbo.instance_details set is_available = 1
    where is_enabled = 1 and is_available = 0 
        and ( sql_instance in ($onlineSqlInstancesCSV) or source_sql_instance in ($onlineSqlInstancesCSV) )
"@
        $conInventoryServer | Invoke-DbaQuery -Database $InventoryDatabase -Query $sqlSetOnlineFlag -EnableException
    }

    if($jobs_exception.Count -gt 0) {
        "{0} {1,-10} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))","(INFO)","Setting [is_available] flag for $($jobs_exception.Count) offline server(s).."
        $offlineSqlInstancesCSV = (($jobs_exception.Name | % {"'$_'"}) -join ',')
        $sqlSetOfflineFlag = @"
    update dbo.instance_details set is_available = 0, last_unavailability_time_utc = SYSUTCDATETIME()
    where is_enabled = 1 and is_available = 1 
        and ( sql_instance in ($offlineSqlInstancesCSV) or source_sql_instance in ($offlineSqlInstancesCSV) )
"@
        $conInventoryServer | Invoke-DbaQuery -Database $InventoryDatabase -Query $sqlSetOfflineFlag -EnableException
    }

    $errMessage

    "`n$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Script completed."
}
else {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'WARNING:', "No SQLServers to check availability."
}

$timeTaken = New-TimeSpan -Start $currentTime -End $(Get-Date)
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Execution completed in $($timeTaken.TotalSeconds) seconds."

# F:\GitHub\SQLMonitor\SQLMonitor\check-instance-availability.ps1 -InventoryServer SQLMonitor -Debug