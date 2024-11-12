[CmdletBinding()]
Param (
    [Parameter(Mandatory=$true)]
    $Server,
    
    [Parameter(Mandatory=$false)]
    [PSCredential]$Credential
)

# First Attempt without Any credentials
try {
        "Trying for PSSession on [$Server] normally.." | Write-Verbose
        $ssn = New-PSSession -ComputerName $Server -ErrorAction SilentlyContinue
    }
catch { $errVariables += $_ }

# Second Attempt for Trusted Cross Domains
if( [String]::IsNullOrEmpty($ssn) ) {
    try { 
        "Trying for PSSession on [$Server] assuming cross domain.." | Write-Verbose
        $ssn = New-PSSession -ComputerName $Server -Authentication Negotiate  -ErrorAction SilentlyContinue
    }
    catch { $errVariables += $_ }
}

# 3rd Attempt with Credentials
if( [String]::IsNullOrEmpty($ssn) -and (-not [String]::IsNullOrEmpty($Credential)) ) {
    try {
        "Attemping PSSession for [$Server] using provided WindowsCredentials.." | Write-Verbose
        $ssn = New-PSSession -ComputerName $Server -Credential $Credential -ErrorAction SilentlyContinue
    }
    catch { $errVariables += $_ }

    if( [String]::IsNullOrEmpty($ssn) ) {
        "Attemping PSSession for [$Server] using provided WindowsCredentials with Negotiate attribute.." | Write-Verbose
        $ssn = New-PSSession -ComputerName $Server -Credential $Credential -Authentication Negotiate -ErrorAction SilentlyContinue
    }
}

if ( [String]::IsNullOrEmpty($ssn) ) {
    "Check if Server is pingable & Credential are valid." | Write-Error
}
else {
    "Return session.." | Write-Verbose
    $ssn
}