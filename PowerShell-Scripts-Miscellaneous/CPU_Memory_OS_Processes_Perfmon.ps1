# Get top processes with CPU Utilization
$cores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors

Get-Counter "\Process(*)\% Processor Time" |
Select -ExpandProperty CounterSamples |
Select InstanceName,
@{Name = "CPU_Percent"; Expression = { [math]::Round($_.CookedValue / $cores, 2) } } |
Where-Object { $_.CPU_Percent -gt 0 } | Sort-Object -Property CPU_Percent -Descending | ogv




# Get Memory Utilization using Perfmon
Get-Counter "\Process(*)\Working Set" |
Select -ExpandProperty CounterSamples |
Select InstanceName, @{l = 'MemoryMB'; e = { [math]::Round($_.CookedValue / 1024.0 / 1024.0, 2) } } |
Sort-Object -Property MemoryMB -Descending | Select * -First 20



# Get Memory Utilization using Get-Process
$procGroups = Get-Process |
Select Name, Id,
@{n = "WorkingSet(MB)"; e = { [math]::Round($_.WorkingSet64 / 1MB, 2) } },
@{n = "Private(MB)"; e = { [math]::Round($_.PrivateMemorySize64 / 1MB, 2) } } |
Group-Object -Property Name

[System.Collections.ArrayList]$allProcesses = @()
foreach ($group in $procGroups) {
  $procName = $group.Name
  $procCount = $group.Count
  $procInstances = @()
  $procInstances += $group.Group
  $procMemoryTotal = 0.0

  foreach ($inst in $procInstances) {
    $instMem = $inst.'WorkingSet(MB)'
    $procMemoryTotal = $procMemoryTotal + $instMem
  }

  $allProcesses.Add([PSCustomObject]@{Name = $procName; WorkingSet_MB = $procMemoryTotal })
}

$allProcesses | Sort-Object -Property WorkingSet_MB -Descending | Select -First 20 | ogv

