[CmdletBinding()]
Param (
    [Parameter(Mandatory=$false)]
    [String]$Name
)

if([String]::IsNullOrEmpty($Name)) {
    Write-Output "Hello there!"
}
else {
    Write-Output "Hello $Name!"
}