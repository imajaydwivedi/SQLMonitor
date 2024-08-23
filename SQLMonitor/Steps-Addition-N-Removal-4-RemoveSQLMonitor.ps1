[CmdletBinding()]
Param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("AddStep", "RemoveStep")]
    [String]$Action = "AddStep",

    [Parameter(Mandatory=$false)]
    [String]$StepName = "70__DropTable_Blitz",
    
    [Parameter(Mandatory=$false)]
    [String[]]$AllSteps = @( "1__Remove_SQLAgentAlerts", "2__RemoveJob_CaptureAlertMessages", "3__RemoveJob_CheckSQLAgentJobs",
                "4__RemoveJob_CollectAgHealthState", "5__RemoveJob_CollectDiskSpace", "6__RemoveJob_CollectOSProcesses",
                "7__RemoveJob_CollectPerfmonData", "8__RemoveJob_CollectPrivilegedInfo", "9__RemoveJob_CollectWaitStats",
                "10__RemoveJob_CollectXEvents", "11__RemoveJob_PartitionsMaintenance", "12__RemoveJob_PurgeTables",
                "13__RemoveJob_RemoveXEventFiles", "14__RemoveJob_RunWhoIsActive", "15__RemoveJob_CollectFileIOStats",
                "16__RemoveJob_CollectMemoryClerks", "17__RemoveJob_RunBlitz", "18__RemoveJob_RunBlitzIndex",
                "19__RemoveJob_RunLogSaver", "20__RemoveJob_RunTempDbSaver", "21__RemoveJob_UpdateSqlServerVersions",
                "22__RemoveJob_CheckInstanceAvailability", "23__RemoveJob_GetAllServerInfo", "24__RemoveJob_GetAllServerCollectedData",
                "25__DropProc_UspExtendedResults", "26__DropProc_UspCollectWaitStats", "27__DropProc_UspRunWhoIsActive",
                "28__DropProc_UspCollectXEventsXEventMetrics", "29__DropProc_UspPartitionMaintenance", "30__DropProc_UspPurgeTables",
                "31__DropProc_SpWhatIsRunning", "32__DropProc_UspActiveRequestsCount", "33__DropProc_UspCollectFileIOStats",
                "34__DropProc_UspEnablePageCompression", "35__DropProc_UspWaitsPerCorePerMinute", "36__DropProc_UspCollectMemoryClerks",
                "37__DropProc_UspAvgDiskWaitMs", "38__DropProc_UspCaptureAlertMessages", "39__DropProc_UspCheckSqlAgentJobs",
                "40__DropProc_UspCollectAgHealthState", "41__DropProc_UspCollectPrivilegedInfo", "42__DropProc_UspCollectXEventMetrics",
                "43__DropProc_UspCreateAgentAlerts", "44__DropProc_UspLogSaver", "45__DropProc_UspTempDbSaver",
                "46__DropProc_UspWrapperCollectPriviledgedInfo", "47__DropProc_UspWrapperGetAllServerInfo", "48__DropProc_UspPopulateAllServerVolatileInfoHistory",
                "49__DropProc_UspGetAllServerInfo", "50__DropView_VwPerformanceCounters", "51__DropView_VwOsTaskList",
                "52__DropView_VwWaitStatsDeltas", "53__DropView_vw_file_io_stats_deltas", "54__DropView_vw_xevent_metrics",
                "55__DropView_vw_disk_space", "56__DropView_vw_all_server_info", "57__DropXEvent_XEventMetrics",
                "58__DropLinkedServer", "59__DropLogin_Grafana", "60__DropTable_XEventMetrics",
                "61__DropTable_xevent_metrics_queries", "62__DropTable_XEventMetricsProcessedXELFiles", "63__DropTable_WhoIsActive_Staging",
                "64__DropTable_WhoIsActive", "65__DropTable_PerformanceCounters", "66__DropTable_PurgeTable",
                "67__DropTable_PerfmonFiles", "68__DropTable_InstanceDetails", "69__DropTable_InstanceHosts",
                "70__DropTable_Blitz", "71__DropTable_OsTaskList", "72__DropTable_BlitzWho",
                "73__DropTable_BlitzCache", "74__DropTable_ConnectionHistory", "75__DropTable_BlitzFirst",
                "76__DropTable_BlitzFirstFileStats", "77__DropTable_DiskSpace", "78__DropTable_BlitzFirstPerfmonStats",
                "79__DropTable_BlitzFirstWaitStats", "80__DropTable_BlitzFirstWaitStatsCategories", "81__DropTable_WaitStats",
                "82__DropTable_BlitzIndex", "83__DropTable_FileIOStats", "84__DropTable_MemoryClerks",
                "85__DropTable_AgHealthState", "86__DropTable_LogSpaceConsumers", "87__DropTable_PrivilegedInfo",
                "88__DropTable_SqlAgentJobStats", "89__DropTable_SqlAgentJobThresholds", "90__DropTable_TempdbSpaceConsumers",
                "91__DropTable_TempdbSpaceUsage", "92__DropTable_AllServerCollectionLatencyInfo", "93__DropTable_AllServerVolatileInfoHistory",
                "94__DropTable_AllServerVolatileInfo", "95__DropTable_AllServerStableInfo", "96__DropTable_DiskSpaceAllServers",
                "97__DropTable_LogSpaceConsumersAllServers", "98__DropTable_LogSpaceConsumersAllServersStaging", "99__DropTable_SqlAgentJobsAllServers",
                "100__DropTable_SqlAgentJobsAllServersStaging", "101__DropTable_TempdbSpaceUsageAllServers", "102__DropTable_TempdbSpaceUsageAllServersStaging",
                "103__DropTable_AgHealthStateAllServers", "104__DropTable_AgHealthStateAllServersStaging", "105__DropTable_AllServerVolatileInfoHistory",
                "106__DropTable_DiskSpaceAllServersStaging", "107__DropTable_AlertCategories", "108__DropTable_AlertHistory",
                "109__RemovePerfmonFilesFromDisk", "110__RemoveXEventFilesFromDisk", "111__DropProxy",
                "112__DropCredential", "113__RemoveInstanceFromInventory"
                ),

    [Parameter(Mandatory=$false)]
    [Bool]$PrintUserFriendlyFormat = $true,

    [Parameter(Mandatory=$false)]
    [String]$ScriptFile = 'E:\GitHub\SQLMonitor\Work\Remove-SQLMonitor __new.ps1'
)

cls

# Placeholders
$newFinalSteps = @()

# Calculations
[int]$paramStepNo = $StepName -replace "__\w+", ''
$preStepIndex = $paramStepNo-2;
if($Action -eq "AddStep") { # Add New Step
    $existingPostStepIndex = $paramStepNo-1;
    $existingLastStepIndex = $AllSteps.Count-1;
}
else { # Remove Existing Step
    $existingPostStepIndex = $paramStepNo;
    $existingLastStepIndex = $AllSteps.Count-1;
}

Write-Debug "Step here for debugging"

# Logically previous steps remain same irrespective of Addition/Removal of steps
$newPreSteps = @()
if( $preStepIndex -ne -1) {
    $newPreSteps += $AllSteps[0..$preStepIndex]
}

# Create array with all the new steps including pre & post
$newPostSteps = @()
if($Action -eq "AddStep") { # Add New Step
    $newPostSteps += $AllSteps[$existingPostStepIndex..$existingLastStepIndex] | 
        ForEach-Object {[int]$stepNo = $_ -replace "__\w+", ''; $_.Replace("$stepNo", "$($stepNo+1)")}
    $newFinalSteps = $newPreSteps + @($StepName) + $newPostSteps
}
else { # Remove Existing Step
    $newPostSteps += $AllSteps[$existingPostStepIndex..$existingLastStepIndex] | 
        ForEach-Object {[int]$stepNo = $_ -replace "__\w+", ''; $_.Replace("$stepNo", "$($stepNo-1)")}
    $newFinalSteps = $newPreSteps + $newPostSteps
}



"All New Steps => `n`n " | Write-Host -ForegroundColor Green
if($PrintUserFriendlyFormat) {
    foreach($num in $(0..$([Math]::Floor($newFinalSteps.Count/3)))) {
        $numStart = ($num*3)
        $numEnd = ($num*3)+2
        #"`$num = $num, `$numStart = $numStart, `$numEnd = $numEnd"        
        
        "                " + $(($newFinalSteps[$numStart..$numEnd] | ForEach-Object {'"'+$_+'"'}) -join ', ') + $(if($num -ne $([Math]::Floor($newFinalSteps.Count/3))){","})
        
    }
}
else {
    $newFinalSteps
}

if([String]::IsNullOrEmpty($ScriptFile)) {
    "`n`nNo file provided to replace the content."
} else {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Read file content.."
    $fileContent = [System.IO.File]::ReadAllText($ScriptFile)
    foreach($index in $($existingPostStepIndex..$($AllSteps.Count-1))) 
    {
        if($Action -eq "AddStep") { # Add New Step
            $fileContent = $fileContent.Replace($AllSteps[$index],$newFinalSteps[$index+1]);
        }
        else { # Remove Existing Step
            $fileContent = $fileContent.Replace($AllSteps[$index],$newFinalSteps[$index-1]);
        }
    }

    # Check if script file is temp or original
    if(Test-Path $ScriptFile) {
        $scriptFileObj = Get-Item $ScriptFile
        $scriptFileName = $scriptFileObj.Name
    }
    
    if($scriptFileName -eq 'Remove-SQLMonitor') {
        $newScriptFile = $ScriptFile.Replace('.ps1',' __bak.ps1')
    }
    else {
        $newScriptFile = $ScriptFile
    }
    $fileContent | Out-File -FilePath $newScriptFile

    if($scriptFileName -eq 'Remove-SQLMonitor') {
        notepad $newScriptFile
    }
    "Updated data saved into file '$newScriptFile'." | Write-Host -ForegroundColor Green
    "Opening saved file '$newScriptFile'." | Write-Host -ForegroundColor Green
}

