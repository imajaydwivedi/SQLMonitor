<#	Combine multiple PerfMon files into One
#>

$sqlDiagOutputFolder = 'T:\Perfmon-Files-Evidences\Perfmon-Files';
$perfmonFiles = Get-ChildItem $sqlDiagOutputFolder -Recurse | Where-Object { $_.Extension -eq '.BLG' -and $_.Name -notlike 'SQLDIAG_*' };

$startTime = Get-Date

"Total $($perfmonFiles.Count) perfmon files found." | Write-Host -ForegroundColor Green

# relog allows max 32 files in single operation. So divide the files in batches. Using $batchSize variable to control
$batchSize = 30
$totalBatches = ([int][Math]::Floor($perfmonFiles.Count / $batchSize)) + 1

"Need $totalBatches batches for processing Total $($perfmonFiles.Count) perfmon files." | Write-Host -ForegroundColor Green

[System.Collections.ArrayList]$batchOutputFiles = @()

for ($batch = 1; $batch -le $totalBatches; $batch++) {
  "Working on batch $batch.." | Write-Host -ForegroundColor Cyan

  # assume all files initially
  $batchStartIndex = 0
  $batchEndIndex = $perfmonFiles.Count - 1
  $AllArgs = @();

  if ($totalBatches -le 1) {
    $batchCombinedFile = "$sqlDiagOutputFolder\SQLDIAG_Combined_$($startTime.ToString('yyyyMMMdd_HHmm')).BLG"
  }
  else {
    $batchCombinedFile = "$sqlDiagOutputFolder\SQLDIAG_Batch_$($batch)of$($totalBatches)_$($startTime.ToString('yyyyMMMdd_HHmm')).BLG"
    $batchStartIndex = ($batch - 1) * $batchSize
    $batchEndIndex = if ($batch -eq $totalBatches) { $batchStartIndex + ($perfmonFiles.Count % $batchSize) - 1 } else { ($batch * $batchSize) - 1 }
  }

  "`tProcessing files $batchStartIndex-$batchEndIndex.." | Write-Host -ForegroundColor Cyan

  for ($counter = $batchStartIndex; $counter -le $batchEndIndex; $counter++) {
    New-Variable -Name "blgFile$counter" -Value $perfmonFiles[$counter].FullName -Force;
    $AllArgs += $perfmonFiles[$counter].FullName;
  }
  $AllArgs += @('-f', 'bin', '-o', $batchCombinedFile);

  & 'relog.exe' $AllArgs
  $batchOutputFiles.Add($batchCombinedFile) | Out-Null
}

$combinedFile = $batchCombinedFile
if ($totalBatches -gt 1) {
  "Combine batch output files into one file.." | Write-Host -ForegroundColor Green

  $AllArgs = @();
  $combinedFile = "$sqlDiagOutputFolder\SQLDIAG_Combined_$($startTime.ToString('yyyyMMMdd_HHmm')).BLG"
  foreach ($file in $batchOutputFiles) {
    $AllArgs += $file  
  }
  $AllArgs += @('-f', 'BIN', '-o', $combinedFile);

  & 'relog.exe' $AllArgs
}

"`nFinal file '$combinedFile' is generated." | Write-Host -ForegroundColor Green
