[CmdletBinding()]
Param (
    [Parameter(Mandatory=$false)]
    $TemplatePath = “C:\SQLMonitor\DBA_PerfMon_All_Counters_Template.xml”,
    [Parameter(Mandatory=$false)]
    $CollectorSetName = "DBA",
    [Parameter(Mandatory=$false)]
    [bool]$WhatIf = $false,
    [Parameter(Mandatory=$false)]
    [bool]$ReSetupCollector = $false
)

$modulePath = [Environment]::GetEnvironmentVariable('PSModulePath')
$modulePath += ';C:\Program Files\WindowsPowerShell\Modules'
[Environment]::SetEnvironmentVariable('PSModulePath', $modulePath)

Import-Module dbatools
$ErrorActionPreference = 'Stop'

# Find Perfmon data collection logs folder path
$collector_root_directory = Split-Path $TemplatePath -Parent
$log_file_path = "$collector_root_directory\Perfmon-Files\$CollectorSetName"
$file_rotation_time = '00:05:00'
$sample_interval = '00:00:30'

if($ReSetupCollector) {
    # Remove existing data collector
    $pfCollector = @()
    $pfCollector += Get-DbaPfDataCollector -CollectorSet $CollectorSetName
    if($pfCollector.Count -gt 0) 
    {
        "Data Collector [$CollectorSetName] exists." | Write-Host -ForegroundColor Cyan
        
        logman stop -name $CollectorSetName
        logman delete -name $CollectorSetName
        "Data Collector Set [$CollectorSetName] removed." | Write-Host -ForegroundColor Cyan    
    }
}

# Get named instances installed on box
"Finding sql instances on host.." | Write-Host -ForegroundColor Cyan
$sqlInstances = @()
$dbaServices = @()

$dbaServices += Get-DbaService -Type Engine
$sqlInstances +=  ($dbaServices | ? {$_.InstanceName -ne 'MSSQLSERVER'} | Select-Object -ExpandProperty ServiceName)
#$sqlInstances +=  (Get-Service *sql* | ? {$_.Name -ne 'MSSQLSERVER' -and $_.DisplayName -match '^SQL Server \(.+\)$'} | Select-Object -ExpandProperty Name)


# read template data into xml object
[xml]$xmlDoc = (Get-Content $TemplatePath)

# Add counters for named instances, or Process counters in case of 1+ SQLInstances
if( ($sqlInstances.Count -gt 0) -or ($dbaServices.Count -gt 1) )
{
    # segregate sql, process & os counters
    $sqlInstanceCounters = @()
    $processCounters = @()
    $otherCounters = @()

    foreach($cntr in $xmlDoc.DataCollectorSet.PerformanceCounterDataCollector.Counter) {
        if($cntr -match '^\\SQLServer:.*') {
            $sqlInstanceCounters += $cntr
        }
        elseif( ($cntr -match '^\\Process\(sqlservr\)\\.*') -or ($cntr -match '^\\Process\(sqlagent\)\\.*') ) {
            $processCounters += $cntr
        }
        else {
            $otherCounters += $cntr
        }
    }

    if ($sqlInstances.Count -gt 0)
    {
        "Add counters for named instances ($($sqlInstances -join ',')).." | Write-Host -ForegroundColor Cyan
        # https://stackoverflow.com/questions/16428559/powershell-script-to-update-xml-file-content    
        
        # Loop through each named instance
        foreach($sqlInst in $sqlInstances) {
            # Loop through each sql counter
            foreach($cntr in $sqlInstanceCounters) {
                $counterElement = $xmlDoc.CreateElement("Counter")
                $counterElement.InnerText = $cntr.Replace('\SQLServer:',('\'+$sqlInst+':'))
                $xmlDoc.DataCollectorSet.PerformanceCounterDataCollector.AppendChild($counterElement) | Out-Null
            }
        }
    }

    if ($dbaServices.Count -gt 1)
    {
        $loopLimit = ($dbaServices.Count - 1)

        "Add counters for SQL/Agent Process for '$loopLimit' more SQLInstances.." | Write-Host -ForegroundColor Cyan
        # https://github.com/imajaydwivedi/SQLMonitor/issues/11
        
        #$processCounters = @()

        # Loop through each named instance
        foreach($index in $(1..$loopLimit)) 
        {
            # Loop through each process engine counter
            foreach($cntr in $processCounters) 
            {
                $counterElement = $xmlDoc.CreateElement("Counter")
                if ($cntr -match '^\\Process\(sqlservr\)\\.*') {
                    $counterElement.InnerText = $cntr.Replace('(sqlservr)',('('+"sqlservr#$index"+')'))
                }
                else {
                    $counterElement.InnerText = $cntr.Replace('(sqlagent)',('('+"sqlagent#$index"+')'))
                }
                $xmlDoc.DataCollectorSet.PerformanceCounterDataCollector.AppendChild($counterElement) | Out-Null
            }
        }
    }
}


#save the changes made in template data into a temp file
$tempFile = $collector_root_directory+"\$(Get-Random).xml"
"Creating new temporary template file '$tempFile'.." | Write-Host -ForegroundColor Cyan
$xmlDoc.Save($tempFile)

$TemplatePath = $tempFile

# Create data collector from template, update sample & rotation time, and start collector
if(-not $WhatIf) {
    "Creating Collector Set [$CollectorSetName] from template [$TemplatePath].." | Write-Host -ForegroundColor Cyan
    logman import -name “$CollectorSetName” -xml “$TemplatePath”
    "Updating Collector Set [$CollectorSetName] with sample interval, rotation time, and output file path.." | Write-Host -ForegroundColor Cyan
    logman update -name “$CollectorSetName” -f bin -cnf "$file_rotation_time" -o "$log_file_path" -si "$sample_interval"
    "Starting Collector Set [$CollectorSetName].." | Write-Host -ForegroundColor Cyan
    logman start -name “$CollectorSetName”
}

if([System.IO.File]::Exists($tempFile)) {
    "Removing temporary template file [$tempFile].." | Write-Host -ForegroundColor Cyan
    Remove-Item -Path $tempFile -WhatIf:$WhatIf
}
<#
logman stop -name “$CollectorSetName”
logman delete -name “$CollectorSetName”

Get-Counter -ListSet * | Select-Object -ExpandProperty Counter | ogv
#>

<#
C:\SQLMonitor\perfmon-collector-logman.ps1 `
    -TemplatePath 'C:\SQLMonitor\DBA_PerfMon_All_Counters_Template.xml' `
    -ReSetupCollector $true
#>