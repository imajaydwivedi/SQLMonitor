$currentTime = Get-Date
$durationString = ($currentTime.AddMinutes(1)).ToString('HH:mm')

$taskPath = '\SQLDBATools\'
$arguments = "-nologo -Noninteractive -noprofile -ExecutionPolicy BYPASS -File 'C:\SQLMonitor\Say-Hello.ps1' -Name 'Ajay'"
$doStuff = New-ScheduledTaskAction -Execute 'powershell' -Argument $arguments
$timeToDoStuff = New-ScheduledTaskTrigger -Daily -DaysInterval 1 -RandomDelay "00:30" -At $durationString
$timeToDoStuff.Repetition = $(New-ScheduledTaskTrigger -Once -RandomDelay "00:30" -At $durationString -RepetitionDuration "23:59" -RepetitionInterval "00:05").Repetition
$settingsForTheStuff = New-ScheduledTaskSettingsSet
$runAsUser = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$finalBuildOfTheStuff = New-ScheduledTask -Action $doStuff -Trigger $timeToDoStuff -Settings $settingsForTheStuff -Principal $runAsUser -Description "Run DBA Job Every 5 minutes"

$taskObj = @()
$taskObj += Get-ScheduledTask -TaskName "DBA-Job-Test" -TaskPath $taskPath
if([String]::IsNullOrEmpty($taskObj)) {
    "Create task.."
    Register-ScheduledTask -TaskName "DBA-Job-Test" -InputObject $finalBuildOfTheStuff -TaskPath $taskPath
}
else {
    "Drop & Recreate task.."
    $taskObj | Unregister-ScheduledTask -Confirm:$false
    Register-ScheduledTask -TaskName "DBA-Job-Test" -InputObject $finalBuildOfTheStuff -TaskPath $taskPath
}

Start-ScheduledTask -TaskName 'DBA-Job-Test' -TaskPath $taskPath
