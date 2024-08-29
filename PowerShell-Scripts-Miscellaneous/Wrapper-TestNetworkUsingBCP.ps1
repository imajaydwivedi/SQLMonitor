[CmdletBinding()]
Param (
    [Parameter(Mandatory=$false)]
    [String]$DataSourceServer = 'OfficeLaptop',
    [Parameter(Mandatory=$false)]
    [String]$DataSourceDb = 'DBA',
    [Parameter(Mandatory=$false)]
    [int]$Threads = 2,
    [Parameter(Mandatory=$false)]
    [String]$DestinationDirectory = "D:\",
    [Parameter(Mandatory=$false)]
    [int]$DaysThreshold = 0,
    [Parameter(Mandatory=$false)]
    [bool]$ExecuteGeneratedBatchFiles = $true,
    [Parameter(Mandatory=$false)]
    [bool]$ExecuteSerially = $false,
    [Parameter(Mandatory=$false)]
    [String]$SQLUser = 'grafana',
    [Parameter(Mandatory=$false)]
    [String]$SQLUserPassword = 'grafana',
    [Parameter(Mandatory=$false)]
    [DateTime]$CollectionTime,
    [Parameter(Mandatory=$false)]
    [String]$ExecutionLogFile = 'Wrapper-TestNetworkUsingBCP.txt',
    [Parameter(Mandatory=$false)]
    [Bool]$CleanupFilesBeforeActivity = $true
)

$ErrorActionPreference = 'STOP'
$startTime = Get-Date

if([String]::IsNullOrEmpty($CollectionTime)) {
    $CollectionTime = Get-Date
}
$CollectionTimeString = $(Get-Date -Format yyyyMMMdd_HHmm)


# Add backslash
if(-not $DestinationDirectory.EndsWith('\')) {
    $DestinationDirectory = "$DestinationDirectory\"
}

# If a drive letter, then add folder name automatically
if($DestinationDirectory.Length -le 3) {
    $DestinationDirectory = "$($DestinationDirectory)DBA-Network-Test\"
}

$dataFilesDirectory = "$($DestinationDirectory)DataFiles"
$batchFilesDirectory = "$($DestinationDirectory)BatchFiles"
$resultsDirectory = "$($DestinationDirectory)Results"

# Check batchFilesDirectory folder
if(-not (Test-Path $batchFilesDirectory)) {
    New-Item $batchFilesDirectory -ItemType Directory -Force | Out-Null
}

# Check dataFilesDirectory folder
if(-not (Test-Path $dataFilesDirectory)) {
    New-Item $dataFilesDirectory -ItemType Directory -Force | Out-Null
}

# Check resultsDirectory folder
if(-not (Test-Path $resultsDirectory)) {
    New-Item $resultsDirectory -ItemType Directory -Force | Out-Null
}

# Cleanup old files 
if($CleanupFilesBeforeActivity) {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Removing old files.." | Write-Verbose
    Get-ChildItem -Path $batchFilesDirectory -Include *.* -File -Recurse | foreach { $_.Delete()} | Out-Null
    Get-ChildItem -Path $dataFilesDirectory -Include *.* -File -Recurse | foreach { $_.Delete()} | Out-Null
    Get-ChildItem -Path $resultsDirectory -Include *.* -File -Recurse | foreach { $_.Delete()} | Out-Null
}

$ExecutionLogFilePath = "$($DestinationDirectory)$ExecutionLogFile"

# Check Log File existence
if(-not(Test-Path $ExecutionLogFilePath)) {
    New-Item -Path $ExecutionLogFile -ItemType File | Out-Null
}

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'START:', "Starting Networking Test.." | Tee-Object $ExecutionLogFilePath -Append | Write-Host -ForegroundColor Yellow
$PSBoundParameters | Tee-Object $ExecutionLogFilePath -Append

# Check SQL login
if([String]::IsNullOrEmpty($SQLUser) -or [String]::IsNullOrEmpty($SQLUserPassword)) {
    "Parameters SQLUser & SQLUserPassword are not provided. So using Trusted Authentication." | Write-Host -ForegroundColor Yellow
}

# Loop, and generate batch files
[int]$counter = 1
[System.Collections.ArrayList]$BatchProcesses = @()
[System.Collections.ArrayList]$ResultFiles = @()
while ($counter -le $Threads) {
    $outputDataFile = "$dataFilesDirectory\DBA_BCP_Test_$counter.dat"
    $outputBatchFile = "$batchFilesDirectory\DBA_BCP_Test_Batch_$counter.bat"
    $outputLogFile = "$resultsDirectory\$($CollectionTimeString)__DBA_BCP_Test_Batch_$counter`__Result.txt"

    $ResultFiles.Add($outputLogFile) | Out-Null
    
    if($DaysThreshold -eq 0) {
        $scriptCode = "BCP `"select * from dbo.vw_performance_counters pc where pc.collection_time_utc between dateadd(hour,-1,getutcdate()) and getutcdate()`" "
    }
    else {
        $scriptCode = "BCP `"select * from dbo.vw_performance_counters pc where pc.collection_time_utc between dateadd(day,-$($DaysThreshold+1),getutcdate()) and dateadd(day,-1,getutcdate())`" "
    }
    $scriptCode = $scriptCode +" queryout `"$outputDataFile`" -S $DataSourceServer -d $DataSourceDb -o $outputLogFile "
    if(-not [String]::IsNullOrEmpty($SQLUserPassword)) {
        $scriptCode = $scriptCode +" -U `"$SQLUser`" -P `"$SQLUserPassword`" "
    } else {
        $scriptCode = $scriptCode +" -T "
    }
    $scriptCode = $scriptCode +" -a 65535 -c -t`"!~!`""
    $scriptCode | Out-File $outputBatchFile -Force ascii
    #"`n'$outputBatchFile' generated." | Write-Host -ForegroundColor Green

    # If required, then execute the batch files here
    if($ExecuteGeneratedBatchFiles) 
    {
        # If executed Parallel
        if($ExecuteSerially -eq $false) 
        {
            # Start-Job -ScriptBlock { Get-Process -Name $args } -ArgumentList powershell, pwsh, notepad
            $job = Start-Job -Name "Wrapper-TestNetworkUsingBCP-$counter" -ScriptBlock { $batchProcResult = Start-Process -FilePath $Using:outputBatchFile -Wait:$true -PassThru; $batchProcResult}
            $BatchProcesses.Add($job) | Out-Null
        }

        # If executed serially
        if($ExecuteSerially) 
        {
            $batchProcResult = Start-Process -FilePath $outputBatchFile -Wait:$true -passthru;

            if($batchProcResult.ExitCode -eq 0) {
                "`tBatch executed successfully." | Write-Host -ForegroundColor Green
            }
            else {
                "`tBatch execution failed. Kindly execute manually." | Write-Host -ForegroundColor DarkRed
            }
        }
    }

    $counter += 1
}

if($ExecuteSerially -eq $false) {
    $BatchProcesses | Wait-Job | Out-Null
    #$BatchProcesses | Get-Job | Out-Null
    $batchProcessResult = @()
    $batchProcessResult += $BatchProcesses | Receive-Job | Out-Null
    $BatchProcesses | Remove-Job | Out-Null
}

$EndTime = Get-Date

$elapsedTime = New-TimeSpan -Start $startTime -End $EndTime
$elapsedTimeSeconds = $elapsedTime.TotalSeconds


# Loop, and generate batch files
[int]$counter = 1
$totalSizeMBFiles = 0
$totalSizeBytesFiles = 0
$TotalNetworkTimeSeconds = 0
$TotalNetworkTimeMS = 0
while ($counter -le $Threads) 
{    
    $fileSizeBytes = 0
    $fileSizeMB = 0
    $timeMS = 0
    $timeSeconds = 0
    $packetSizeBytes = 0
    $countPackets = 0

    $outputDataFile = "$dataFilesDirectory\DBA_BCP_Test_$counter.dat"
    $outputBatchFile = "$batchFilesDirectory\DBA_BCP_Test_Batch_$counter.bat"
    $outputLogFile = "$resultsDirectory\$($CollectionTimeString)__DBA_BCP_Test_Batch_$counter`__Result.txt"

    $resultFileContent = Get-Content $outputLogFile -Tail 2
    $fileSizeBytes = $(Get-Item $outputDataFile).Length
    $fileSizeMB = [math]::Ceiling($fileSizeBytes / 1mb)

    "`n$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Result for '$outputLogFile' => `n" | Tee-Object $ExecutionLogFilePath -Append
    "File size => $fileSizeMB mb" | Tee-Object $ExecutionLogFilePath -Append
    $resultFileContent | Tee-Object $ExecutionLogFilePath -Append
    
    $timeRow = $resultFileContent[1]
    $timePattern = "^Clock Time \(ms\.\) Total     : (?<timeMS>\d+)\s+"
    if($timeRow -match $timePattern) {
        $timeMS = $Matches['timeMS']
        $timeSeconds = [math]::Ceiling($timeMS/1000)
    }

    $packetSizeRow = $resultFileContent[0]
    $packetSizePattern = "^Network packet size \(bytes\): (?<packetSizeBytes>\d+)"
    if($packetSizeRow -match $packetSizePattern) {
        $packetSizeBytes = $Matches['packetSizeBytes']
    }

    $countPackets = $fileSizeBytes / $packetSizeBytes

    if(-not $ExecuteSerially) {
        if($timeSeconds -gt $TotalNetworkTimeSeconds) {
            $TotalNetworkTimeSeconds = $timeSeconds
            $TotalNetworkTimeMS = $timeMS
        }
    } else {
        $TotalNetworkTimeSeconds += $timeSeconds
    }
    

    $totalSizeMBFiles = $totalSizeMBFiles + $fileSizeMB
    $totalSizeBytesFiles = $totalSizeBytesFiles + $fileSizeBytes

    "_"*20  | Tee-Object $ExecutionLogFilePath -Append #| Out-Null

    $counter += 1
}

$throughPut = [math]::Ceiling($totalSizeMBFiles/$TotalNetworkTimeSeconds)
$packetsTotal = [math]::Ceiling($totalSizeBytesFiles / $packetSizeBytes)
$latencyMS = [math]::Ceiling($TotalNetworkTimeMS/$packetsTotal)

"`n{0,-20} {1}" -f 'Data Transferred:', "$totalSizeMBFiles MB" | Tee-Object $ExecutionLogFilePath -Append
"{0,-20} {1}" -f 'Throughput:', "$($totalSizeMBFiles/$TotalNetworkTimeSeconds) mbps" | Tee-Object $ExecutionLogFilePath -Append
"{0,-20} {1}" -f 'Latency:', "$latencyMS ms" | Tee-Object $ExecutionLogFilePath -Append

"`n$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'RESULT:', "Total time taken for Data Transfer: $TotalNetworkTimeSeconds seconds." | Tee-Object $ExecutionLogFilePath -Append | Write-Host -ForegroundColor Yellow
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'END:', "End of Networking Test." | Tee-Object $ExecutionLogFilePath -Append | Write-Host -ForegroundColor Green
"*"*80  | Tee-Object $ExecutionLogFilePath -Append | Out-Null
"*"*80  | Tee-Object $ExecutionLogFilePath -Append | Out-Null

<#

D:\GitHub-Personal\SQLMonitor\PowerShell-Scripts-Miscellaneous\Wrapper-TestNetworkUsingBCP.ps1 `
        -DataSourceServer OfficeLaptop -DataSourceDb DBA -DestinationDirectory "D:\" `
        -Threads 2 -ExecuteGeneratedBatchFiles $true -ExecuteSerially $false -DaysThreshold 1 `
        -SQLUser grafana -SQLUserPassword grafana

#>