[CmdletBinding()]
Param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("AddStep", "RemoveStep")]
    [String]$Action = "AddStep",

    [Parameter(Mandatory=$false)]
    [String]$StepName = "42__CreateJobSendLoginExpiryEmails",
    
    [Parameter(Mandatory=$false)]
    [String[]]$AllSteps = @( "1__sp_WhoIsActive", "2__AllDatabaseObjects", "3__XEventSession",
                "4__FirstResponderKitObjects", "5__DarlingDataObjects", "6__OlaHallengrenSolutionObjects",
                "7__sp_WhatIsRunning", "8__usp_GetAllServerInfo", "9__CopyDbaToolsModule2Host",
                "10__CopyPerfmonFolder2Host", "11__SetupPerfmonDataCollector", "12__CreateCredentialProxy",
                "13__CreateJobCollectDiskSpace", "14__CreateJobCollectOSProcesses", "15__CreateJobCollectPerfmonData",
                "16__CreateJobCollectWaitStats", "17__CreateJobCollectXEvents", "18__CreateJobCollectFileIOStats",
                "19__CreateJobPartitionsMaintenance", "20__CreateJobPurgeTables", "21__CreateJobRemoveXEventFiles",
                "22__CreateJobRunLogSaver", "23__CreateJobRunTempDbSaver", "24__CreateJobRunWhoIsActive",
                "25__CreateJobRunBlitzIndex", "26__CreateJobRunBlitz", "27__CreateJobRunBlitzIndexWeekly",
                "28__CreateJobCollectMemoryClerks", "29__CreateJobCollectPrivilegedInfo", "30__CreateJobCollectAgHealthState",
                "31__CreateJobCheckSQLAgentJobs", "32__CreateJobCaptureAlertMessages", "33__CreateSQLAgentAlerts",
                "34__CreateJobUpdateSqlServerVersions", "35__CreateJobCheckInstanceAvailability", "36__CreateJobGetAllServerInfo",
                "37__CreateJobGetAllServerCollectedData", "38__CreateJobGetAllServerDashboardMail", "39__CreateJobStopStuckSQLMonitorJobs",
                "40__CreateJobCollectLoginExpirationInfo", "41__CreateJobPopulateInventoryTables", "42__CreateJobSendLoginExpiryEmails",
                "43__WhoIsActivePartition", "44__BlitzIndexPartition", "45__BlitzPartition",
                "46__EnablePageCompression", "47__GrafanaLogin", "48__LinkedServerOnInventory",
                "49__LinkedServerForDataDestinationInstance", "50__AlterViewsForDataDestinationInstance"
                ),

    [Parameter(Mandatory=$false)]
    [Bool]$PrintUserFriendlyFormat = $true,

    [Parameter(Mandatory=$false)]
    [String]$ScriptFile = 'D:\GitHub-Personal\SQLMonitor\SQLMonitor\Install-SQLMonitor.ps1'
)

cls

# Placeholders
$finalSteps = @()

# Calculations
[int]$paramStepNo = $StepName -replace "__\w+", ''
$preStep = $paramStepNo-2;
if($Action -eq "AddStep") { # Add New Step
    $postStep = $paramStepNo-1;
    $lastStep = $AllSteps.Count-1;
}
else { # Remove Existing Step
    $postStep = $paramStepNo;
    $lastStep = $AllSteps.Count-1;
}

Write-Debug "Step here for debugging"

#"Pre-Steps" | Write-Host -ForegroundColor Green
$preNewSteps = @()
if( ($Action -eq "AddStep") -and ($preStep -ne -1) ) {
    $preNewSteps += $AllSteps[0..$preStep]
}

#"`nAdd step '$StepName' here`n" | Write-Host -ForegroundColor Cyan

#"Post-Steps" | Write-Host -ForegroundColor Green
$postNewSteps = @()
if($Action -eq "AddStep") { # Add New Step
    $postNewSteps += $AllSteps[$postStep..$lastStep] | 
        ForEach-Object {[int]$stepNo = $_ -replace "__\w+", ''; $_.Replace("$stepNo", "$($stepNo+1)")}
    $finalSteps = $preNewSteps + @($StepName) + $postNewSteps
}
else { # Remove Existing Step
    $postNewSteps += $AllSteps[$postStep..$lastStep] | 
        ForEach-Object {[int]$stepNo = $_ -replace "__\w+", ''; $_.Replace("$stepNo", "$($stepNo-1)")}
    $finalSteps = $preNewSteps + $postNewSteps
}



"All New Steps => `n`n " | Write-Host -ForegroundColor Green
if($PrintUserFriendlyFormat) {
    foreach($num in $(0..$([Math]::Floor($finalSteps.Count/3)))) {
        $numStart = ($num*3)
        $numEnd = ($num*3)+2
        #"`$num = $num, `$numStart = $numStart, `$numEnd = $numEnd"        
        
        "                " + $(($finalSteps[$numStart..$numEnd] | ForEach-Object {'"'+$_+'"'}) -join ', ') + $(if($num -ne $([Math]::Floor($finalSteps.Count/3))){","})
        
    }
}
else {
    $finalSteps
}

if([String]::IsNullOrEmpty($ScriptFile)) {
    "`n`nNo file provided to replace the content."
} else {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Read file content.."
    $fileContent = [System.IO.File]::ReadAllText($ScriptFile)
    foreach($index in $($postStep..$($AllSteps.Count-1))) 
    {
        if($Action -eq "AddStep") { # Add New Step
            $fileContent = $fileContent.Replace($AllSteps[$index],$finalSteps[$index+1]);
        }
        else { # Remove Existing Step
            $fileContent = $fileContent.Replace($AllSteps[$index],$finalSteps[$index-1]);
        }
    }
    $newScriptFile = $ScriptFile.Replace('.ps1',' __bak.ps1')
    $fileContent | Out-File -FilePath $newScriptFile
    notepad $newScriptFile
    "Updated data saved into file '$newScriptFile'." | Write-Host -ForegroundColor Green
    "Opening saved file '$newScriptFile'." | Write-Host -ForegroundColor Green
}

