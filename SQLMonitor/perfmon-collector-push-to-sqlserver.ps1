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
    $TablePerfmonFiles = '[dbo].[perfmon_files]',

    [Parameter(Mandatory=$false)]
    $TablePerfmonCounters = '[dbo].[performance_counters]',

    [Parameter(Mandatory=$false)]
    $CollectorSetName = 'DBA',

    [Parameter(Mandatory=$false)]
    $ErrorActionPreference = 'Stop',

    [Parameter(Mandatory=$false)]
    [Bool]$RemoveProcessedFileImmediately = $true,

    [Parameter(Mandatory=$false)]
    [Bool]$CleanupFiles = $true,

    [Parameter(Mandatory=$false)]
    [int]$FileCleanupThresholdHours = 48,

    [Parameter(Mandatory=$false)]
    [Bool]$SkipStopStartDataCollector = $false
)

$startTime = Get-Date

$modulePath = [Environment]::GetEnvironmentVariable('PSModulePath')
$modulePath += ';C:\Program Files\WindowsPowerShell\Modules'
[Environment]::SetEnvironmentVariable('PSModulePath', $modulePath)

Import-Module dbatools
$ErrorActionPreference = 'Stop'

# Fetch Collector details
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Fetch details of [$collectorSetName] data collector.."

$dataCollectorSet = New-Object -COM Pla.DataCollectorSet;
$dataCollectorSet.Query($CollectorSetName,$HostName);

$computerName = $dataCollectorSet.Server
$lastFile = $dataCollectorSet.DataCollectors[0].LatestOutputLocation
if([String]::IsNullOrEmpty($lastFile)) {
    $pfCollectorFolder = "$PSScriptRoot\Perfmon-Files"
}
else {
    $pfCollectorFolder = Split-Path $lastFile -Parent
}
$lastImportedFile = $null

# Create Server Object
$sqlInstanceObj = Connect-DbaInstance -SqlInstance $SqlInstance -ClientName "(dba) Collect-PerfmonData" -TrustServerCertificate -EncryptConnection -ErrorAction Stop

# Get latest imported file
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Fetch details of last imported file from [$SqlInstance].[$Database].$TablePerfmonFiles.."
$lastImportedFile = $sqlInstanceObj | Invoke-DbaQuery -Database $Database -Query "select top 1 file_name from $TablePerfmonFiles where host_name = '$computerName' and file_name like '$computerName%' order by file_name desc" | Select-Object -ExpandProperty file_name;
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "`$lastImportedFile => '$lastImportedFile'."

# Stop collector set
if ($SkipStopStartDataCollector) {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Skipping step where we stop data collector.."
}
else {
    if($dataCollectorSet.Status -eq 1) {
        "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Stop data collector.."
        #$pfCollectorSet | Stop-DbaPfDataCollectorSet | Out-Null
        $dataCollectorSet.Stop($true) | Out-Null
    }
}

# Note existing files
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Scan existing perfmon files generated.."
$perfmonFilesFound = @()
$pfCollectorFiles = @()
$perfmonFilesDirectory = $("\\$computerName\"+$pfCollectorFolder.Replace(':','$'))
$isSharedPathValid = $false

try {
    if (Test-Path $perfmonFilesDirectory) {$isSharedPathValid = $true}
}
catch {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'WARNING:', "`$perfmonFilesDirectory '$perfmonFilesDirectory' failed Test-Path validation."
}
if (-not $isSharedPathValid) {
    if($env:COMPUTERNAME -eq $computerName) {
        $perfmonFilesDirectory = $pfCollectorFolder
    }
    else {
        Write-Error "Path `$perfmonFilesDirectory => '$perfmonFilesDirectory' is not reachable." -ErrorAction Stop
    }
}
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "`$perfmonFilesDirectory => '$perfmonFilesDirectory'."
$perfmonFilesFound += Get-ChildItem $perfmonFilesDirectory -Recurse -File -Name *.blg
[String]$latestPerfmonFile = $null
if($perfmonFilesFound.Count -gt 0) {
    $latestPerfmonFile = ($perfmonFilesFound | Sort-Object -Descending)[0]
}
if($SkipStopStartDataCollector) {
    $pfCollectorFiles += $perfmonFilesFound | Where-Object {([String]::IsNullOrEmpty($lastImportedFile) -or ($_ -gt $lastImportedFile)) -and ([String]::IsNullOrEmpty($latestPerfmonFile) -or ($_ -lt $latestPerfmonFile))} | Sort-Object
} else {
    $pfCollectorFiles += $perfmonFilesFound | Where-Object {[String]::IsNullOrEmpty($lastImportedFile) -or ($_ -gt $lastImportedFile)} | Sort-Object
}
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "$($perfmonFilesFound.Count) files found. $($pfCollectorFiles.Count) qualify for import into tables."

# Start collector set
if ($SkipStopStartDataCollector) {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Skip step of Starting data collector.."
}
else {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Start data collector.."
    #Start-DbaPfDataCollectorSet -ComputerName $computerName -CollectorSet $collectorSetName | Out-Null
    $dataCollectorSet.start($true)
}

# Get DB Engine Services to extract ProcessId & InstanceName
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Get DbaServices on '$HostName'.."
$dbaServices = @()
$dbaServices += Get-DbaService -ComputerName $HostName -Type Engine | Select-Object InstanceName, ProcessId

$SqlProcessesRaw = @()
$SqlProcesses = @()
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Get SQLServer Process ID(s) on '$HostName'.."
if($HostName -ne $env:COMPUTERNAME) {
    $SqlProcessesRaw += (Get-counter -ComputerName $HostName -counter "\Process(sqlservr*)\ID Process").CounterSamples
} else {
    $SqlProcessesRaw += (Get-counter -counter "\Process(sqlservr*)\ID Process").CounterSamples
}
$SqlProcesses += $SqlProcessesRaw | Select-Object @{l='SqlProcessId';e={
        $path=$_.Path; 
        if($path -match '\\Process\((?<SqlProcessId>sqlservr#?\d{0,2})\)\\.*'){
            $Matches.SqlProcessId
        }else {
            $path
        }
        }}, 
        @{l='InstanceName'; e={
            $processId = $_.CookedValue;
            $instanceName = $dbaServices | Where-Object {$_.ProcessId -eq $processId} | Select-Object -ExpandProperty InstanceName -First 1;
            $instanceName
        }},
        @{l='ProcessId';e={$_.CookedValue}}


foreach($file in $pfCollectorFiles)
{
    "`n$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Processing file '$file', and import data into [$SqlInstance].[$Database].$TablePerfmonCounters.."
    try
    {
        $perfmonFilePath = "$("\\$computerName\"+$pfCollectorFolder.Replace(':','$'))\$file"
        if(-not (Test-Path $perfmonFilePath)) {
            if($env:COMPUTERNAME -eq $computerName) {
                $perfmonFilePath = "$pfCollectorFolder\$file"
            }
        }
        Import-Counter -Path "$perfmonFilePath" -EA silentlycontinue | 
            Select-Object -ExpandProperty CounterSamples | #Select-Object * -First 5 | 
                Select-Object @{l='collection_time_utc';e={($_.TimeStamp).ToUniversalTime()}}, `
                              @{l='host_name';e={$computerName}}, `
                              @{l='object';e={
                                    $path = $_.Path; 
                                    $pathWithoutComputerName = ($path -replace "\\\\$computerName", '');
                                    if($pathWithoutComputerName -match '^\\(?<ObjectInstance>.+)\\(?<Counter>.+)') {
                                        $objectInstance = $Matches.ObjectInstance
                                        
                                        if($objectInstance -match '^(?<Object>.+)\((?<Instance>.+)\)') {
                                            $object = $Matches.Object
                                        }
                                        else {
                                            $object = $objectInstance
                                        }
                                    }
                                    $object
                               }}, `
                              @{l='counter';e={
                                    $path = $_.Path; 
                                    $pathWithoutComputerName = ($path -replace "\\\\$computerName", '');
                                    if($pathWithoutComputerName -match '^\\(?<ObjectInstance>.+)\\(?<Counter>.+)') {
                                        $objectInstance = $Matches.ObjectInstance
                                        $counter = $Matches.Counter
                                    }
                                    $counter
                               }}, `
                              @{l='value';e={$_.CookedValue}}, `
                              @{l='instance';e={
                                    $path = $_.Path; 
                                    $pathWithoutComputerName = ($path -replace "\\\\$computerName", '');
                                    if($pathWithoutComputerName -match '^\\(?<ObjectInstance>.+)\\(?<Counter>.+)') {
                                        $objectInstance = $Matches.ObjectInstance
                                        $counter = $Matches.Counter
                                        if($objectInstance -match '^(?<Object>.+)\((?<Instance>.+)\)') {
                                            $object = $Matches.Object
                                            $instance = $Matches.Instance
                                        }
                                        else {
                                            $object = $objectInstance
                                            $instance = $_.InstanceName
                                        }
                                    }

                                    if($object -eq 'process' -and $instance -like 'sqlservr*') {
                                        $instanceName = $SqlProcesses | Where-Object {$_.SqlProcessId -eq $instance} | Select-Object -ExpandProperty InstanceName -First 1;
                                        $instance = "sqlservr`$$instanceName"
                                    }

                                    $instance
                               }} | 
                Write-DbaDbTableData -SqlInstance $sqlInstanceObj -Database $Database -Table $TablePerfmonCounters -EnableException
        "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "File import complete.."

    
        # If blg file is read successfully, then add file entry into database
        "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Make entry of file in [$SqlInstance].[$Database].$TablePerfmonFiles.."
        $sqlInsertFile = @"
        insert $TablePerfmonFiles (host_name, file_name, file_path)
        select @host_name, @file_name, @file_path;
"@
        $sqlInstanceObj | Invoke-DbaQuery -Database $Database -Query $sqlInsertFile -SqlParameter @{host_name = $computerName; file_name = $file; file_path = "$pfCollectorFolder\$file"} -EnableException
        "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Entry made.."

        if($CleanupFiles -and $RemoveProcessedFileImmediately) {
            "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Remove file.."
            Remove-Item "$perfmonFilePath"
            "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "File removed.."
        }
        else {
            "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "File removal skipped due to parameter RemoveProcessedFileImmediately."
        }
    }
    catch {
        $errMessage = $_;
        $errMessage.Exception | Select * | fl

        # Handle error "No valid counter paths were found in the files" which happens when OS is restarted, and file becomes invalid
        if($errMessage.Exception.Message -like '*No valid counter paths were found in the files*')
        {
            "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'ERROR:', "Got error '$($errMessage.Exception.Message)' while reading '$file'."

            "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Trying to skip the file.." 
            $sqlInsertFile = @"
            insert $TablePerfmonFiles (host_name, file_name, file_path)
            select @host_name, @file_name, @file_path;
"@
            $sqlInstanceObj | Invoke-DbaQuery -Database $Database -Query $sqlInsertFile -SqlParameter @{host_name = $computerName; file_name = $file; file_path = "$pfCollectorFolder\$file"} -EnableException
            "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Skip Entry made into [$SqlInstance].[$Database].$TablePerfmonFiles.."

            # Try to remove file for which we got error
            try {
                "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Remove file as its generating error.."
                Remove-Item "$perfmonFilePath"
                "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "File removed.."
            }
            catch {
                "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'ERROR:', "Failed to remove file due to error '$($_.Exception.Message)'.."
            }
        }
    }
}

# Remove older files
if($CleanupFiles) {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Search files older than $FileCleanupThresholdHours hours.."
    $oldFilesForCleanup = @()
    $oldFilesForCleanup += Get-ChildItem $perfmonFilesDirectory -Recurse -File | `
                                Where-Object { ($_.Name -like '*.blg') -and ($_.LastWriteTimeUtc -lt $startTime.AddHours(-$FileCleanupThresholdHours).ToUniversalTime()) }

    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "$($oldFilesForCleanup.Count) files detected older than $FileCleanupThresholdHours hours."
    if($oldFilesForCleanup.Count -gt 0) {
        "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Remove above detected old files.."
        $oldFilesForCleanup | Remove-Item -ErrorAction Ignore | Out-Null
    }    
}

"`n`n$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'END:', "All files processed.."

