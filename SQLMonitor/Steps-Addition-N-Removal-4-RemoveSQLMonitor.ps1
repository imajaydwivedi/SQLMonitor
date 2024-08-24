[CmdletBinding()]
Param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("AddStep", "RemoveStep")]
    [String]$Action = "AddStep",

    [Parameter(Mandatory=$false)]
    [String]$StepName = "73__DropView_SmaSqlServersIncludingOffline",

    [Parameter(Mandatory=$false)]
    [Bool]$PrintUserFriendlyFormat = $true,

    [Parameter(Mandatory=$false)]
    [String]$ScriptFile = 'E:\GitHub\SQLMonitor\Work\Remove-SQLMonitor __new.ps1',

    [Parameter(Mandatory=$false)]
    [bool]$SkipFileContentWriting = $true
)

cls

# Placeholders
$newFinalSteps = @()

# Read Script File Content
if(-not (Test-Path $ScriptFile)) {
    "Kindly provide ScriptFile." | Write-Error -ErrorAction Stop
}
else {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Read file content.."
    $fileContent = [System.IO.File]::ReadAllText($ScriptFile)

    if([String]::IsNullOrEmpty($fileContent)) {
        "Provided ScriptFile seems empty." | Write-Error -ErrorAction Stop
    }
}

# Extract AllSteps from Script File Content, and dynamically create a $AllSteps variable
$allStepsPatternInFile = '\$AllSteps = \@\((\s*(?<steps>(\"\d+_{2}\w+\",?\s?)+\n)+(\s+\"\d+_{2}\w+\",?)+)\n?\s*\)'
if($fileContent -match $allStepsPatternInFile) {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "AllSteps pattern found in script file.."
    $cmd2CreateStepsVariable = $Matches[0]
    $cmd2cr
    Invoke-Expression $cmd2CreateStepsVariable
}

# Check if $AllSteps is present
if(-not ($AllSteps -is [array])) {
    "Seems could not extract AllSteps from Script File content." | Write-Error -ErrorAction Stop
}


# Check if $StepName is already present
if($StepName -in $AllSteps) {
    "Seems specified step is already present in Script File." | Write-Error -ErrorAction Stop
}

# Calculations of Step Index
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
if( (-not [String]::IsNullOrEmpty($newFilecontent)) -and ($SkipFileContentWriting -eq $false) ) {
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


