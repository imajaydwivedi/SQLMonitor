[CmdletBinding()]
Param (
    # Set SQL Server where data should be saved
    [Parameter(Mandatory=$false)]
    $SqlInstance = 'localhost',

    [Parameter(Mandatory=$false)]
    $Database = 'master',

    [Parameter(Mandatory=$false)]
    $GitHubURL = 'https://raw.githubusercontent.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/dev/SqlServerVersions.sql'
)

Import-Module dbatools;

$ErrorActionPreference = 'Stop'
$currentTime = Get-Date

$verbose = $false;
if ($PSBoundParameters.ContainsKey('Verbose')) { # Command line specifies -Verbose[:$false]
    $verbose = $PSBoundParameters.Get_Item('Verbose')
}

$debug = $false;
if ($PSBoundParameters.ContainsKey('Debug')) { # Command line specifies -Debug[:$false]
    $debug = $PSBoundParameters.Get_Item('Debug')
}

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Fetch file from Internet.."
$SqlServerVersionsQuery = (Invoke-WebRequest $GitHubURL -UseBasicParsing).Content

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Execute query against [$SqlInstance].[$Database].SqlServerVersions.."
$sqlInstanceObj = Connect-DbaInstance -SqlInstance $SqlInstance -ClientName "(dba) Update-SqlServerVersions" -TrustServerCertificate -EncryptConnection -ErrorAction Stop
$sqlInstanceObj | Invoke-DbaQuery -Database $Database -Query $SqlServerVersionsQuery -EnableException -MessagesToOutput:$verbose;

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'SUCCESS:', "Script completed successfully."

