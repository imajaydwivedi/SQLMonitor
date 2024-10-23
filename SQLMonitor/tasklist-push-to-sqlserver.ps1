[CmdletBinding()]
Param (
    # Set SQL Server where data should be saved
    [Parameter(Mandatory=$false)]
    $SqlInstance = 'localhost',

    [Parameter(Mandatory=$false)]
    $Database = 'DBA',

    [Parameter(Mandatory=$false)]
    $HostName = $env:COMPUTERNAME,

    [Parameter(Mandatory=$false)]
    $TableName = '[dbo].[os_task_list]'
)

$modulePath = [Environment]::GetEnvironmentVariable('PSModulePath')
$modulePath += ';C:\Program Files\WindowsPowerShell\Modules'
[Environment]::SetEnvironmentVariable('PSModulePath', $modulePath)

Import-Module dbatools

$ErrorActionPreference = 'Stop'
$timeUTC = (Get-Date).ToUniversalTime()

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Get running processes on OS `$taskList.."
$taskList = @()
if($HostName -eq $env:COMPUTERNAME -or $HostName -eq 'localhost') {
    if($HostName -eq 'localhost') {
        $HostName = $env:COMPUTERNAME
    }
    $taskList += TASKLIST /v /fo csv | ConvertFrom-Csv
}
else {
    $taskList += TASKLIST /s $HostName /v /fo csv | ConvertFrom-Csv
}
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "OS Processes captured in `$taskList."

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Process raw data in `$taskList.."
$processes = @()
$processes += $taskList | Select @{l='collection_time_utc';e={$timeUTC}}, @{l='host_name';e={$HostName}}, @{l='task_name';e={$_.'Image Name'}}, @{l='pid';e={$_.PID}}, `
                @{l='session_name';e={$_.'Session Name'}}, @{l='memory_kb';e={$mem = $_.'Mem Usage'; [bigint]($mem.Replace(',', '') -replace ' K','')}}, `
                @{l='status';e={$status = $_.'Status'; if($status -eq 'Unknown'){$null}else{$_.'Status'}}}, `
                @{l='user_name';e={$_.'User Name'}}, @{l='cpu_time';e={$_.'CPU Time'}}, `
                @{l='cpu_time_seconds';e={$cpu_time_parts = $($_.'CPU Time') -split ':'; (New-TimeSpan -Hours $cpu_time_parts[0] -Minutes $cpu_time_parts[1] -Seconds $cpu_time_parts[2]).TotalSeconds}}, `
                @{l='window_title';e={$title = $_.'Window Title'; if($title -eq 'N/A'){$null}else{$title}}}

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "$($processes.Count) processes found.."

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "$(($processes | Where-Object {$_.memory_kb -gt 0 -or $_.cpu_time_seconds -gt 0}).Count) processes found consuming cpu or memory over 1 kb."
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Push filtered os processes info to SqlServer [$SqlInstance].[$Database].$TableName.."
$sqlInstanceObj = Connect-DbaInstance -SqlInstance $SqlInstance -ClientName "(dba) Collect-OSProcesses" -TrustServerCertificate -EncryptConnection -ErrorAction Stop
$processes | Where-Object {$_.memory_kb -gt 0 -or $_.cpu_time_seconds -gt 0} |
        Write-DbaDbTableData -SqlInstance $sqlInstanceObj -Database $Database -Table $TableName -EnableException

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Export completed in $((New-TimeSpan -Start $timeUTC -End (Get-Date).ToUniversalTime()).TotalSeconds) seconds."
