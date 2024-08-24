[CmdletBinding()]
Param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("AddStep", "RemoveStep")]
    [String]$Action = "AddStep",

    [Parameter(Mandatory=$false)]
    [String]$StepName = "30__RemoveJob_StopStuckSQLMonitorJobs",
    
    [Parameter(Mandatory=$false)]
    [String[]]$AllSteps = @( "1__Remove_SQLAgentAlerts", "2__RemoveJob_CaptureAlertMessages", "3__RemoveJob_CheckSQLAgentJobs",
                "4__RemoveJob_CollectAgHealthState", "5__RemoveJob_CollectDiskSpace", "6__RemoveJob_CollectOSProcesses",
                "7__RemoveJob_CollectPerfmonData", "8__RemoveJob_CollectPrivilegedInfo", "9__RemoveJob_CollectWaitStats",
                "10__RemoveJob_CollectXEvents", "11__RemoveJob_PartitionsMaintenance", "12__RemoveJob_PurgeTables",
                "13__RemoveJob_RemoveXEventFiles", "14__RemoveJob_RunWhoIsActive", "15__RemoveJob_CollectFileIOStats",
                "16__RemoveJob_CollectMemoryClerks", "17__RemoveJob_RunBlitz", "18__RemoveJob_RunBlitzIndex",
                "19__RemoveJob_RunLogSaver", "20__RemoveJob_RunTempDbSaver", "21__RemoveJob_UpdateSqlServerVersions",
                "22__RemoveJob_CheckInstanceAvailability", "23__RemoveJob_GetAllServerInfo", "24__RemoveJob_GetAllServerCollectedData",
                "25__RemoveJob_CollectLoginExpirationInfo", "26__RemoveJob_CollectAllServerAlertMessages", "27__RemoveJob_GetAllServerDashboardMail",
                "28__RemoveJob_PopulateInventoryTables", "29__RemoveJob_SendLoginExpiryEMails", "30__RemoveJob_StopStuckSQLMonitorJobs",
                "31__DropProc_UspExtendedResults", "32__DropProc_UspCollectWaitStats", "33__DropProc_UspRunWhoIsActive",
                "34__DropProc_UspCollectXEventsXEventMetrics", "35__DropProc_UspPartitionMaintenance", "36__DropProc_UspPurgeTables",
                "37__DropProc_SpWhatIsRunning", "38__DropProc_UspActiveRequestsCount", "39__DropProc_UspCollectFileIOStats",
                "40__DropProc_UspEnablePageCompression", "41__DropProc_UspWaitsPerCorePerMinute", "42__DropProc_UspCollectMemoryClerks",
                "43__DropProc_UspAvgDiskWaitMs", "44__DropProc_UspCaptureAlertMessages", "45__DropProc_UspCheckSqlAgentJobs",
                "46__DropProc_UspCollectAgHealthState", "47__DropProc_UspCollectPrivilegedInfo", "48__DropProc_UspCollectXEventMetrics",
                "49__DropProc_UspCreateAgentAlerts", "50__DropProc_UspLogSaver", "51__DropProc_UspTempDbSaver",
                "52__DropProc_UspWrapperCollectPriviledgedInfo", "53__DropProc_UspWrapperGetAllServerInfo", "54__DropProc_UspPopulateAllServerVolatileInfoHistory",
                "55__DropProc_UspGetAllServerInfo", "56__DropView_VwPerformanceCounters", "57__DropView_VwOsTaskList",
                "58__DropView_VwWaitStatsDeltas", "59__DropView_vw_file_io_stats_deltas", "60__DropView_vw_xevent_metrics",
                "61__DropView_vw_disk_space", "62__DropView_vw_all_server_info", "63__DropXEvent_XEventMetrics",
                "64__DropLinkedServer", "65__DropLogin_Grafana", "66__DropTable_XEventMetrics",
                "67__DropTable_xevent_metrics_queries", "68__DropTable_XEventMetricsProcessedXELFiles", "70__DropTable_WhoIsActive_Staging",
                "70__DropTable_WhoIsActive", "71__DropTable_PerformanceCounters", "72__DropTable_PurgeTable",
                "73__DropTable_PerfmonFiles", "74__DropTable_InstanceDetails", "75__DropTable_InstanceHosts",
                "76__DropTable_Blitz", "77__DropTable_OsTaskList", "78__DropTable_BlitzWho",
                "79__DropTable_BlitzCache", "80__DropTable_ConnectionHistory", "81__DropTable_BlitzFirst",
                "82__DropTable_BlitzFirstFileStats", "83__DropTable_DiskSpace", "84__DropTable_BlitzFirstPerfmonStats",
                "85__DropTable_BlitzFirstWaitStats", "86__DropTable_BlitzFirstWaitStatsCategories", "87__DropTable_WaitStats",
                "88__DropTable_BlitzIndex", "89__DropTable_FileIOStats", "90__DropTable_MemoryClerks",
                "91__DropTable_AgHealthState", "92__DropTable_LogSpaceConsumers", "93__DropTable_PrivilegedInfo",
                "94__DropTable_SqlAgentJobStats", "95__DropTable_SqlAgentJobThresholds", "96__DropTable_TempdbSpaceConsumers",
                "97__DropTable_TempdbSpaceUsage", "98__DropTable_AllServerCollectionLatencyInfo", "100__DropTable_AllServerVolatileInfoHistory",
                "100__DropTable_AllServerVolatileInfo", "101__DropTable_AllServerStableInfo", "102__DropTable_DiskSpaceAllServers",
                "103__DropTable_LogSpaceConsumersAllServers", "104__DropTable_LogSpaceConsumersAllServersStaging", "105__DropTable_SqlAgentJobsAllServers",
                "106__DropTable_SqlAgentJobsAllServersStaging", "107__DropTable_TempdbSpaceUsageAllServers", "108__DropTable_TempdbSpaceUsageAllServersStaging",
                "109__DropTable_AgHealthStateAllServers", "110__DropTable_AgHealthStateAllServersStaging", "111__DropTable_AllServerVolatileInfoHistory",
                "112__DropTable_DiskSpaceAllServersStaging", "113__DropTable_AlertCategories", "114__DropTable_AlertHistory",
                "115__RemovePerfmonFilesFromDisk", "116__RemoveXEventFilesFromDisk", "117__DropProxy",
                "118__DropCredential", "119__RemoveInstanceFromInventory"
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


"Creating String Matrix of `"New Steps`"..`n " | Write-Host -ForegroundColor Green
$newFinalStepsCount = $newFinalSteps.Count
$newFinalStepsLastIndex = $newFinalStepsCount-1
[String]$newFinalStepsStringMatrix = ''
[String]$newFinalStepsStringMatrix2Replace = ''
if($PrintUserFriendlyFormat) {
    foreach($num in $(0..$([Math]::Floor($newFinalStepsCount/3)))) {
        $numStart = ($num*3)
        $numEnd = ($num*3)+2
        if($numEnd -gt $newFinalStepsLastIndex) {$numEnd = $newFinalStepsLastIndex}
        
        $currentRowStepsCSV = $(($newFinalSteps[$numStart..$numEnd] | ForEach-Object {'"'+$_+'"'}) -join ', ') + $( if($numEnd -ne $newFinalStepsLastIndex) {","})
        $currentRowSteps = "                " + $currentRowStepsCSV
        
        $newFinalStepsStringMatrix = $newFinalStepsStringMatrix + "`n" + $currentRowSteps
        if($num -eq 0) {
            $newFinalStepsStringMatrix2Replace = $currentRowStepsCSV
        }
        else {
            $newFinalStepsStringMatrix2Replace = $newFinalStepsStringMatrix2Replace + "`n" + $currentRowSteps
        }
        #"`$num = $num, `$numStart = $numStart, `$numEnd = $numEnd, `$newFinalStepsCount = $newFinalStepsCount, `$newFinalStepsLastIndex = $newFinalStepsLastIndex, `$newFinalStepsCount/3 = $($newFinalStepsCount/3)"        
        
        #"                " + $(($newFinalSteps[$numStart..$numEnd] | ForEach-Object {'"'+$_+'"'}) -join ', ') + $(if($num -ne $([Math]::Floor($newFinalSteps.Count/3))){","})
        #"                " + $(($newFinalSteps[$numStart..$numEnd] | ForEach-Object {'"'+$_+'"'}) -join ', ') + $( if($numEnd -ne $newFinalStepsLastIndex) {","})
        
        if($numEnd -eq $newFinalStepsLastIndex) {
            break;
        }   
    }

    "$newFinalStepsStringMatrix`n"
}


"Creating String Matrix of `"Old Steps`"..`n " | Write-Host -ForegroundColor Green
$oldStepsCount = $AllSteps.Count
$oldStepsLastIndex = $oldStepsCount-1
[String]$oldStepsStringMatrix = ''
if($PrintUserFriendlyFormat) {
    foreach($num in $(0..$([Math]::Floor($oldStepsCount/3)))) {
        $numStart = ($num*3)
        $numEnd = ($num*3)+2
        if($numEnd -gt $oldStepsLastIndex) {$numEnd = $oldStepsLastIndex}

        $currentRowStepsCSV = $(($AllSteps[$numStart..$numEnd] | ForEach-Object {'"'+$_+'"'}) -join ', ') + $( if($numEnd -ne $oldStepsLastIndex) {","})        
        $currentRowSteps = "                " + $currentRowStepsCSV
        $oldStepsStringMatrix = $oldStepsStringMatrix + "`n" + $currentRowSteps     

        #$currentRowSteps
        <#
        if([String]::IsNullOrEmpty($oldStepsPattern)) {
            $oldStepsPattern = $currentRowStepsCSV
        }
        else {
            $oldStepsPattern = $oldStepsPattern+'\n\s+'+$currentRowStepsCSV
        }
        #>
        
        if($numEnd -eq $oldStepsLastIndex) {
            break;
        }   
    }

    #"$oldStepsStringMatrix`n"
}

if([String]::IsNullOrEmpty($ScriptFile)) {
    "`n`nNo file provided to replace the content."
} else {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Read file content.."
    $fileContent = [System.IO.File]::ReadAllText($ScriptFile)
}

$newFilecontent = $fileContent
$oldStepsPattern = '(\s*(\"\d+_{2}\w+\",?\s?)+\n){'+$([Math]::Floor($oldStepsCount/3)-1)+'}(\s+\"\d+_{2}\w+\",?)+'
if($fileContent -match $oldStepsPattern) {
    $oldStepsStringMatched = $Matches[0]
    $newFilecontent = $fileContent -replace $oldStepsStringMatched, $newFinalStepsStringMatrix2Replace
}
else {
    "Match not found"
}

# Replace nos of Steps one at a time
if(-not [String]::IsNullOrEmpty($newFilecontent)) {
    foreach($index in $($existingPostStepIndex..$($AllSteps.Count-1))) 
    {
        if($Action -eq "AddStep") { # Add New Step
            $newFilecontent = $newFilecontent.Replace($AllSteps[$index],$newFinalSteps[$index+1]);
        }
        else { # Remove Existing Step
            $newFilecontent = $newFilecontent.Replace($AllSteps[$index],$newFinalSteps[$index-1]);
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
    $newFilecontent | Out-File -FilePath $newScriptFile

    if($scriptFileName -eq 'Remove-SQLMonitor') {
        notepad $newScriptFile
    }
    "Updated data saved into file '$newScriptFile'." | Write-Host -ForegroundColor Green
    "Opening saved file '$newScriptFile'." | Write-Host -ForegroundColor Green
}