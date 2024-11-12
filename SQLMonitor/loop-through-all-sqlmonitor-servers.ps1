# $personal = Get-Credential -UserName 'sa' -Message 'SQL Login'
$InventoryServer = 'SQLMonitor'
$InventoryDatabase = 'DBA'
$sqlGetAllServers = @"
select distinct sql_instance, [database] from dbo.instance_details where is_available = 1
"@

$allServersList = Invoke-DbaQuery -SqlInstance $InventoryServer -Database $InventoryDatabase -Query $sqlGetAllServers -SqlCredential $personal;

$files2Execute = @("D:\GitHub-Personal\SQLMonitor\DDLs\SCH-usp_active_requests_count.sql","D:\GitHub-Personal\SQLMonitor\DDLs\SCH-usp_waits_per_core_per_minute.sql")
$query2Execute = @"
if OBJECT_ID('dbo.usp_GetAllServerInfo') is not null
	exec ('grant execute on object::dbo.usp_GetAllServerInfo TO [grafana]')
go
if OBJECT_ID('dbo.usp_active_requests_count') is not null
	exec ('grant execute on object::dbo.usp_active_requests_count TO [grafana]')
go
if OBJECT_ID('dbo.usp_waits_per_core_per_minute') is not null
	exec ('grant execute on object::dbo.usp_waits_per_core_per_minute TO [grafana]')
go
"@


$failedServers = @()
$successServers = @()
foreach($srv in $allServersList)
{
    $sqlInstance = $srv.sql_instance
    $database = $srv.database

    "Working on [$sqlInstance]" | Write-Host -ForegroundColor Cyan
    try {
        $sqlInstance | Invoke-DbaQuery -Database $database -Query $query2Execute -SqlCredential $personal -EnableException
        <#
        foreach($file in $files2Execute) {            
            "`tExecute file '$file'.." | Write-Host -ForegroundColor Yellow
            $sqlInstance | Invoke-DbaQuery -Database $database -File $file -SqlCredential $personal -EnableException
        }
        #>
        
        $successServers += $sqlInstance
    }
    catch {
        $errMessage = $_
        $failedServers += $sqlInstance
        $errMessage.Exception | Write-Host -ForegroundColor Red
        "`n"
    }
}