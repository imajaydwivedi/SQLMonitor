[CmdletBinding()]
Param (
    # Set SQL Server where data should be saved
    [Parameter(Mandatory=$false)]
    $SqlInstance = 'localhost',

    [Parameter(Mandatory=$false)]
    $Database = 'DBA',

    [Parameter(Mandatory=$false)]
    $TableName = '[dbo].[xevent_metrics_Processed_XEL_Files]',

    [Parameter(Mandatory=$false)]
    $MoveFilesToDirectory

)

$modulePath = [Environment]::GetEnvironmentVariable('PSModulePath')
$modulePath += ';C:\Program Files\WindowsPowerShell\Modules'
[Environment]::SetEnvironmentVariable('PSModulePath', $modulePath)

Import-Module dbatools

$ErrorActionPreference = 'Stop'
$currentTime = Get-Date

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "[Connect-DbaInstance] Create connection for '$SqlInstance'.."
$conSqlInstance = Connect-DbaInstance -SqlInstance $SqlInstance -Database master -ClientName "xevents-remove-processed-files.ps1" -TrustServerCertificate -EncryptConnection

# Check if PortNo is specified
$Port4SqlInstance = $null
$SqlInstanceWithOutPort = $SqlInstance
if($SqlInstance -match "(?'SqlInstance'.+),(?'PortNo'\d+)") {
    $Port4SqlInstance = $Matches['PortNo']
    $SqlInstanceWithOutPort = $Matches['SqlInstance']
}

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Fetch HostName.."
$HostName = $conSqlInstance | Invoke-DbaQuery -Query "Select COALESCE(SERVERPROPERTY('ComputerNamePhysicalNetBIOS'),SERVERPROPERTY('ServerName')) as HostName" -EnableException | 
                    Select-Object -ExpandProperty HostName;


"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Get processed xevent files from $Database.$TableName.."

$sqlFiles2Process = @"
select *
from $TableName f
where f.is_removed_from_disk = 0 and is_processed = 1
order by collection_time_utc asc;
"@

$files2Process = @()
$files2Process += $conSqlInstance | Invoke-DbaQuery -Database $Database -Query $sqlFiles2Process -EnableException
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "$($files2Process.Count) files to process.."

Write-Debug "Stop here"

$sqlUpdateFileEntry = "update $Tablename set is_removed_from_disk = 1 where file_path = @file_path"
foreach($row in $files2Process)
{
    $file = $row.file_path
    $fileOnDisk = $file
    $fileName = Split-Path $fileOnDisk -Leaf
    $fileOnMovedDirectory = $fileOnDisk

    # If file has to be moved, then compute its target name
    if(-not [String]::IsNullOrEmpty($MoveFilesToDirectory)) {
        if($MoveFilesToDirectory.EndsWith('\')) {
            $fileOnMovedDirectory = $MoveFilesToDirectory+$fileName
        } else {
            $fileOnMovedDirectory = $MoveFilesToDirectory+'\'+$fileName
        }
    }

    # Convert file path to UNC if remote server
    if( -not ($HostName -eq $env:COMPUTERNAME -or $HostName -eq 'localhost') ) {
        $fileOnDisk = $("\\$HostName\"+$fileOnDisk.Replace(':','$'))
        if($fileOnMovedDirectory.Contains(':')) {
            $fileOnMovedDirectory = $("\\$HostName\"+$fileOnMovedDirectory.Replace(':','$'))
        }
    }

    if (Test-Path $fileOnDisk) 
    {
        # Move xevent file to another directory if required
        if([String]::IsNullOrEmpty($MoveFilesToDirectory)) # Delete file
        {
            "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Removing '$fileOnDisk' .."
            Remove-Item -Path $fileOnDisk
            if ( -not (Test-Path $fileOnDisk) ) {
                "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "File removed. Proceeding to  update flag [is_removed_from_disk].."
                $conSqlInstance | Invoke-DbaQuery -Database $Database -Query $sqlUpdateFileEntry -SqlParameter @{ file_path = "$file" } -EnableException
                "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Flag updated."
            }
        }
        else { # Move file
            "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Moving file to path '$fileOnMovedDirectory' .."
            Move-Item -Path $fileOnDisk -Destination $fileOnMovedDirectory -ErrorAction Stop
        }
    }
    else {
        "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "File '$fileOnDisk' not present on disk."
        "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Proceeding to  update flag [is_removed_from_disk].."
        $conSqlInstance | Invoke-DbaQuery -Database $Database -Query $sqlUpdateFileEntry -SqlParameter @{ file_path = "$file" } -EnableException
        "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Flag updated."
    }
}



