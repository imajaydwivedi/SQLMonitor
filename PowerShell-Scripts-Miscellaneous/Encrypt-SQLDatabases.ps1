[CmdletBinding()]
Param (
    [Parameter(Mandatory=$false)]
    [String]$SqlInstanceToEncrypt = 'SqlPractice',

    [Parameter(Mandatory=$false)]
    [String[]]$DatabasesToEncrypt,

    [Parameter(Mandatory=$false)]
    [String]$DbaDatabase = 'DBA',

    [Parameter(Mandatory=$false)]
    [String]$InventoryServer = 'SQLMonitor',

    [Parameter(Mandatory=$false)]
    [String]$InventoryDatabase = 'DBA',

    [Parameter(Mandatory=$false)]
    [String]$CredentialManagerServer = 'SQLMonitor',

    [Parameter(Mandatory=$false)]
    [String]$CredentialManagerDatabase = 'DBA',

    [Parameter(Mandatory=$false)]
    [PSCredential]$SqlCredential = $personal,

    [Parameter(Mandatory=$false)]
    [PSCredential]$WindowsCredential,

    [Parameter(Mandatory=$false)]
    [String]$LocalBackupDirectory,

    [Parameter(Mandatory=$false)]
    [String]$RemoteBackupDirectory = 'E:\Work',

    [Parameter(Mandatory=$false)]
    [String]$EncryptionPassword,

    [Parameter(Mandatory=$false)]
    [bool]$DryRun = $true,

    [Parameter(Mandatory=$false)]
    [bool]$ScriptOut = $false,

    [Parameter(Mandatory=$false)]
    [bool]$RenewCertificate = $true,

    [Parameter(Mandatory=$false)]
    [int]$ExpiryDaysThreshold = 365, # if expiring in days

    [Parameter(Mandatory=$false)]
    [int]$ExpiryYearsToSetForCertificate = 5 # set expiry date for certificate from today
)

cls
$startTime = Get-Date
$ErrorActionPreference = "Stop"
$ClientName = "Encrypt-SQLDatabases.ps1"

$scriptOutfile = New-TemporaryFile
$horizontalLine = "`n/* " + ('*' * 50) + " */"

"-- ***** Implement Transparent Data Encryption (TDE) on server [$SqlInstanceToEncrypt]`n`n" | Out-File -FilePath $scriptOutfile

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'START:', "Working on server [$SqlInstanceToEncrypt]." | Write-Host -ForegroundColor Yellow

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "[Connect-DbaInstance] Create connection for InventoryServer '$InventoryServer'.."
$conInventoryServer = Connect-DbaInstance -SqlInstance $InventoryServer -Database $InventoryDatabase -ClientName $ClientName `
                                                    -SqlCredential $SqlCredential -TrustServerCertificate -ErrorAction Stop

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "[Connect-DbaInstance] Create connection for CredentialManagerServer '$CredentialManagerServer'.."
$conCredentialManagerServer = Connect-DbaInstance -SqlInstance $CredentialManagerServer -Database $CredentialManagerDatabase -ClientName $ClientName `
                                                    -SqlCredential $SqlCredential -TrustServerCertificate -ErrorAction Stop

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "[Connect-DbaInstance] Create connection for SqlInstanceToEncrypt '$SqlInstanceToEncrypt'.."
$conSqlInstanceToEncrypt = Connect-DbaInstance -SqlInstance $SqlInstanceToEncrypt -Database master -ClientName $ClientName `
                                                    -SqlCredential $SqlCredential -TrustServerCertificate -ErrorAction Stop

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "[Invoke-DbaQuery] Get basic details of '$SqlInstanceToEncrypt'.."
$sqlBasicDetails = @"
use master;
select	srv_name = '$SqlInstanceToEncrypt',
		at_server_name = @@SERVERNAME,
		server_name = convert(varchar,SERVERPROPERTY('ServerName')),
		domain = default_domain(),
		server_host_name = SERVERPROPERTY('ComputerNamePhysicalNetBIOS'),
		total_database_count = (select count(*) from sys.databases d where d.state_desc = 'ONLINE' and is_read_only = 0 and d.database_id > 4),
		error_log_file = SERVERPROPERTY('ErrorLogFileName'),
        master_key_exists = convert(bit,case when exists (select * from sys.symmetric_keys where name LIKE '%DatabaseMasterKey%') then 1 else 0 end)
"@
$resultBasicDetails = @()
$resultBasicDetails += Invoke-DbaQuery -SqlInstance $conSqlInstanceToEncrypt -Database master -Query $sqlBasicDetails

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "[Invoke-DbaQuery] Get existing encryption status per database.."
$sqlDbEncryptionDetails = @"
USE [master];
-- Check Encryption Status
SELECT  [sql_instance] = '$SqlInstanceToEncrypt',
        [database_name] = d.name, encryption_state_desc, percent_complete, --encryptor_thumbprint,
		[key_algorithm] = ek.key_algorithm + '_'+ convert(varchar,ek.key_length), 
		[certificate_name] = c.name, [certificate_expiry_date] = c.expiry_date, 
		[certificate_expiry_days] = case when c.expiry_date is null then null
                                         when c.expiry_date <= getdate() then 0 
                                         else datediff(day,getdate(),c.expiry_date) 
                                         end,
		[certificate_subject] = c.subject,
		[certificate_start_date] = c.start_date,  c.pvt_key_last_backup_date,
		[encryption_key_create_date] = regenerate_date --encryption_scan_state_desc
FROM sys.databases d
left join sys.dm_database_encryption_keys  ek
	on ek.database_id = d.database_id
left join sys.certificates c
	on c.thumbprint = ek.encryptor_thumbprint
    and c.pvt_key_encryption_type_desc = 'ENCRYPTED_BY_MASTER_KEY'
WHERE 1=1
and d.state_desc = 'ONLINE' 
and is_read_only = 0 
and d.database_id > 4
and d.source_database_id is null
"@
$resultDbEncryptionDetails = @()
$resultDbEncryptionDetails += Invoke-DbaQuery -SqlInstance $conSqlInstanceToEncrypt -Database master -Query $sqlDbEncryptionDetails

#$resultBasicDetails | ogv
#$resultDbEncryptionDetails | ogv

$serverName = $resultBasicDetails.server_name
$serverNameDeSensitized = $serverName.Replace('\','_')
$atServerName = $resultBasicDetails.at_server_name
$domain = $resultBasicDetails.domain
$serverHostName = $resultBasicDetails.server_host_name
$totalDatabaseCount = $resultBasicDetails.total_database_count
$errorLogFile = $resultBasicDetails.error_log_file
$errorLogFileDirectory = $(Split-Path $errorLogFile)
$masterKeyExists = $resultBasicDetails.master_key_exists
$saveEncryptionPassword = $false

# get current & previous certificate
[String]$certificateSubject = $serverName+' Certificate'
[string]$currentCertificateName = $null
[int]$currentCertificateAgeLeft = $null
[string]$previousCertificateName = $null
[bool]$hasCertificateExpired = $false
[bool]$createNewCertificate = $true
[int]$pendingDbCount = 0
[int]$encryptedDbCount = 0
[int]$expiredDbCount = 0

# If there are user databases, then extract info
if($resultDbEncryptionDetails.Count -gt 0)
{
    $currentCertificateName = $resultDbEncryptionDetails | Where-Object {$_.certificate_subject -eq $certificateSubject} | `
                                Sort-Object -Property certificate_start_date -Descending | `
                                Select-Object -ExpandProperty certificate_name -First 1
    
    if(-not [String]::($currentCertificateName)) {
        $currentCertificateAgeLeft = $resultDbEncryptionDetails | Where-Object {$_.certificate_name -eq $currentCertificateName} | `
                                    Select-Object -ExpandProperty certificate_expiry_days -First 1
        $previousCertificateName = $resultDbEncryptionDetails | `
                                    Where-Object { ($_.certificate_subject -eq $certificateSubject) -and ($_.certificate_name -notin @($currentCertificateName)) } | `
                                    Sort-Object -Property certificate_start_date -Descending | `
                                    Select-Object -ExpandProperty certificate_name -First 1
    }

    $pendingDbCount = ($resultDbEncryptionDetails | Where-Object {[String]::IsNullOrEmpty($_.encryption_state_desc)}).Count
    $encryptedDbCount = ($resultDbEncryptionDetails | Where-Object {-not [String]::IsNullOrEmpty($_.encryption_state_desc)}).Count
    $expiredDbCount = ($resultDbEncryptionDetails | Where-Object { (-not [String]::IsNullOrEmpty($_.certificate_expiry_days)) -and ($_.certificate_expiry_days -le $ExpiryDaysThreshold) }).Count
}

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "`$encryptedDbCount = $encryptedDbCount"
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "`$currentCertificateAgeLeft = $currentCertificateAgeLeft"
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "`$ExpiryDaysThreshold = $ExpiryDaysThreshold"
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "`$expiredDbCount = $expiredDbCount"

# has certificates expired?
if( ($encryptedDbCount -gt 0) -and ($currentCertificateAgeLeft -lt $ExpiryDaysThreshold) -and ($expiredDbCount -gt 0) ) {
    $hasCertificateExpired = $true
}
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "`$hasCertificateExpired = $hasCertificateExpired"


# return if no encryption, or no certificate renewal issue
if( $pendingDbCount -eq 0 -and $hasCertificateExpired -eq $false -and $expiredDbCount -eq 0 ) {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'RESULT:', "No database pending for encryption."

    if(-not $ScriptOut) {
        return
    }
}

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Either there are dbs to be encrypted, or certificate renewal is required."

# get new certificate
[String]$certificateName = $null
if($hasCertificateExpired) {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "currentCertificateName: '$currentCertificateName'"    
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Certificate renewal is needed."

    # if certificate name has numbering
    if($currentCertificateName -match ".+__Certificate__(?'cert_no'\d+)*$") {
        $certificateName = $serverNameDeSensitized+'__Certificate'+'__'+$( ([int]$Matches['cert_no'])+1 )
    }
    else {
        $certificateName = $serverNameDeSensitized+'__Certificate'+'__2'
    }
}
else {
    if(-not [String]::IsNullOrEmpty($currentCertificateName)) {
        $certificateName = $currentCertificateName
    }
    else {
        $certificateName = $serverNameDeSensitized+'__Certificate'
    }
}

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Configure Local Backup Directory.."
$backupDirectory = $LocalBackupDirectory
if([String]::IsNullOrEmpty($backupDirectory)) {
    $backupDirectory = $errorLogFileDirectory
}

# If Errorlog path is not found, then use sp_readerrorlog to detect same
if([String]::IsNullOrEmpty($backupDirectory)) {
    $sqlGetErrorLog = "exec sp_readerrorlog 0,1,'Log\ERRORLOG','-e'"
    $resultGetErrorLog = @()
    $resultGetErrorLog += Invoke-DbaQuery -SqlInstance $conSqlInstanceToEncrypt -Database master -Query $sqlGetErrorLog
    if($resultGetErrorLog[0].Text -match "\s+-e\s(?'log_directory'.+)\\ERRORLOG") {
        $backupDirectory = $Matches['log_directory']
    }
}

if(-not $backupDirectory.EndsWith('\')) {
    $backupDirectory = $backupDirectory + '\'
}


# Get Encryption Password if present in CM
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Fetch Encryption Password from Credential Manager.."
$sqlFetchPassword = @"
    -- Get Encryption Password for [$SqlInstanceToEncrypt]
select	top 1 server_ip, server_name, [user_name], 
		[password] = cast(DecryptByPassPhrase(cast(salt as varchar),password_hash ,1, server_ip) as varchar)
from dbo.credential_manager cm
where cm.server_ip = '$SqlInstanceToEncrypt'
and user_name = 'master key'
"@

"`n`n-- Execute below on [$CredentialManagerServer].[$CredentialManagerDatabase]`n" + $sqlFetchPassword + "`nGO`n" | Out-File -FilePath $scriptOutfile -Append
$resultFetchPassword = @()
$resultFetchPassword += Invoke-DbaQuery -SqlInstance $conCredentialManagerServer -Database $CredentialManagerDatabase -Query $sqlFetchPassword

# If password does not exist in credential manager
if($resultFetchPassword.Count -eq 0) {
    $saveEncryptionPassword = $true
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Password not found in Credential Manager."

    if([String]::IsNullOrEmpty($EncryptionPassword)) 
    {
        "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "EncryptionPassword parameter is null."

        if($masterKeyExists) {
            "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'ERROR:', "Master Key on $SqlInstanceToEncrypt exists."
            "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'ERROR:', "But existing Encryption Password not found in Credential Manager or Parameter."

            $sql4Debugging = @"
select * from sys.symmetric_keys where name LIKE '%DatabaseMasterKey%';
select name, state_desc, is_encrypted, is_master_key_encrypted_by_server 
	from sys.databases where name = 'master';

-- encrypt master key by Password
alter master key add encryption by password = '<<<YouMasterDbMasterKeyPasswordHere>>>';
"@
            "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'DEBUG:', "Following code can be used for debugging-`n$sql4Debugging`n"
            "Kindly rectify above error" | Write-Error
        }
        else {
            "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Generate Encryption Password.."
            $EncryptionPassword = -Join("ABCDabcd&@#$%1234".tochararray() | Get-Random -Count 25 | % {[char]$_})
        }
    }
}
else {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Encryption Password found in Credential Manager."

    if( (-not [String]::IsNullOrEmpty($EncryptionPassword)) -and ($EncryptionPassword -ne $resultFetchPassword[0].password) ) {
        "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'ERROR:', "Encryption Password in Credential Manager & Parameter value does not match." | Write-Host -ForegroundColor Red
        "Kindly rectify above error" | Write-Error
    }

    if( [String]::IsNullOrEmpty($EncryptionPassword) ) {
        $EncryptionPassword = $resultFetchPassword[0].password
    }
}


# Save Encryption Password if newly generated
if($saveEncryptionPassword -and (-not [String]::IsNullOrEmpty($EncryptionPassword)) ) 
{
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Save Encryption Password in Credential Manager.."
    $params = @{
                    server_ip = $SqlInstanceToEncrypt
                    server_name = $serverName
                    user_name = 'master key'
                    password_string = $EncryptionPassword
                    remarks = 'Database Master Key'
            }
    Invoke-DbaQuery -SqlInstance $conCredentialManagerServer -Database $CredentialManagerDatabase `
            -Query usp_add_credential -SqlParameter $params -CommandType StoredProcedure -MessagesToOutput -EnableException
}
elseif ($saveEncryptionPassword -and [String]::IsNullOrEmpty($EncryptionPassword) ) {
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'ERROR:', "Encryption Password could not be fetched or initialized." | Write-Host -ForegroundColor Red
        "Kindly rectify above error" | Write-Error
}

$sqlAddEncryptionPasswordOnCredentialManager = @"
    -- Save Encryption Key on Credential Manager
exec dbo.usp_add_credential
			@server_ip = '$SqlInstanceToEncrypt',
			@server_name = '$serverName',
			@user_name = 'master key',
			@password_string = '$EncryptionPassword',
			@remarks = 'Database Master Key';
"@
"`n`n-- Execute below on [$CredentialManagerServer].[$CredentialManagerDatabase]`n" + $sqlAddEncryptionPasswordOnCredentialManager + "`nGO`n`n" | Out-File -FilePath $scriptOutfile -Append


# Initialize Derived Variables
$certificatePath = $backupDirectory + $certificateName + '.crt'
[String]$expiredCertificatePath = $null
if($hasCertificateExpired) {
    $expiredCertificatePath = $backupDirectory + $currentCertificateName + '.crt'
}

$masterKeyPath = $backupDirectory + $serverNameDeSensitized + '__master_key.key'
$privateKeyPath = $backupDirectory + $serverNameDeSensitized + '__private_key.pvk'


# Create Master Key on Target
$sqlCreateMasterKey = @"
-- Create master key on [$SqlInstanceToEncrypt]
use master;
if not exists (select * from sys.symmetric_keys where name LIKE '%DatabaseMasterKey%')
begin    
	exec ('use master; create master key encryption by password = ''$EncryptionPassword'';');
    print 'DMK created';
end
else
    print 'DMK exists';
"@

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Create Master Key.."
$sqlCreateMasterKey + "`nGO`n`n" | Out-File -FilePath $scriptOutfile -Append
if($DryRun) {
    $sqlCreateMasterKey | Write-Host -ForegroundColor Magenta
}
else {
    Invoke-DbaQuery -SqlInstance $conSqlInstanceToEncrypt -Database master -Query $sqlCreateMasterKey `
                    -MessagesToOutput -EnableException | Write-Host -ForegroundColor Cyan
}

$certificateExpiryDate = $startTime.AddYears($ExpiryYearsToSetForCertificate).ToString('yyyyMMdd')

# Create Certificate if required
$sqlCreateCertificate = @"
-- Create certificate on [$SqlInstanceToEncrypt]
declare @sql nvarchar(max);
declare @thumbprint varbinary(64);

select @thumbprint = c.thumbprint from sys.certificates c 
	where issuer_name = '$certificateSubject' and name = '$certificateName';

if @thumbprint is null
begin
	set @sql = 'use master; create certificate [$certificateName] with subject = ''$certificateSubject'', EXPIRY_DATE = ''$certificateExpiryDate'';';
	exec (@sql);
    print 'certificate created';
end
else
	print 'Certificate already exists';
"@

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Create Certificate.."
$sqlCreateCertificate + "`nGO`n`n" | Out-File -FilePath $scriptOutfile -Append
if($DryRun) {
    $sqlCreateCertificate | Write-Host -ForegroundColor Magenta
}
else {
    Invoke-DbaQuery -SqlInstance $conSqlInstanceToEncrypt -Database master -Query $sqlCreateCertificate `
                    -MessagesToOutput -EnableException | Write-Host -ForegroundColor Cyan
}


# Backup current Certificate & expired Certificate if any
$sqlBackupCertificate = @"
-- Backup Certificate & Master Key on [$SqlInstanceToEncrypt]
use master;
go

declare @sql nvarchar(max);
exec xp_create_subdir '$backupDirectory';
go

/* **** If Cleanup of Files is required ****
DECLARE @cmd NVARCHAR(MAX);

SET @cmd = 'xp_cmdshell ''del "$masterKeyPath"''';
EXEC (@cmd); -- remove master key file

SET @cmd = 'xp_cmdshell ''del "$privateKeyPath"'''; 
EXEC (@cmd); -- remove private key file

SET @cmd = 'xp_cmdshell ''del "$certificatePath"'''; 
EXEC (@cmd); -- remove certificate file

$(if($hasCertificateExpired) {'--'}) /*
-- Remove expired certificate if any
SET @cmd = 'xp_cmdshell ''del "$expiredCertificatePath"''';
EXEC (@cmd); -- remove certificate file
$(if($hasCertificateExpired) {'--'}) */
*/
go

-- Backup master key
declare @sql nvarchar(max);
set @sql = 'use master; backup master key to file = ''$masterKeyPath'' encryption by password = ''$EncryptionPassword''';
exec (@sql);
go

-- Backup certificate
declare @sql nvarchar(max);
set @sql = 'use master; backup certificate [$certificateName]
	to file = ''$certificatePath''
	with private key (
		file = ''$privateKeyPath'',
		encryption by password = ''$EncryptionPassword''
	)';
exec (@sql);
go

$(if($hasCertificateExpired) {'--'}) /*
-- Backup expired certificate if any
declare @sql nvarchar(max);
set @sql = 'use master; backup certificate [$currentCertificateName]
	to file = ''$expiredCertificatePath''
	--with private key ( file = ''$privateKeyPath'', encryption by password = ''$EncryptionPassword'' )
    ';
exec (@sql)
$(if($hasCertificateExpired) {'--'}) */

/* IMPORTANT: COPY these files to some secure location Immediately before proceeding */

"@

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Backup certificate & Master Key to [$backupDirectory] on $SqlInstanceToEncrypt.."
$sqlBackupCertificate + "`nGO`n`n" | Out-File -FilePath $scriptOutfile -Append
if($DryRun) {
    $sqlBackupCertificate | Write-Host -ForegroundColor Magenta
}
else {
    Invoke-DbaQuery -SqlInstance $conSqlInstanceToEncrypt -Database master -Query $sqlBackupCertificate `
                    -MessagesToOutput -EnableException | Write-Host -ForegroundColor Cyan
}


# List databases to Encrypt
$sqlGetAllUserDatabases = @"
/* Get list of databases to encrypt: $ClientName */
select [database_name] = d.name, d.state_desc, d.is_read_only, 
		d.is_in_standby, d.is_published, d.is_subscribed,
		rs.is_local, rs.replica_server_name, rs.role_desc
		,dm.mirroring_role_desc, d.is_encrypted,
		encryption_state_desc, percent_complete, --encryptor_thumbprint,
		[key_algorithm] = ek.key_algorithm + '_'+ convert(varchar,ek.key_length), 
		[certificate_name] = c.name, [certificate_expiry_date] = c.expiry_date, 
		[certificate_expiry_days] = case when c.expiry_date <= getdate() then 0 else datediff(day,getdate(),c.expiry_date) end,
		[certificate_subject] = c.subject,
		[certificate_start_date] = c.start_date,  c.pvt_key_last_backup_date,
		[encryption_key_create_date] = regenerate_date --encryption_scan_state_desc
from sys.databases d 
outer apply (select top 1 rs.is_local, ar.replica_server_name, rs.role_desc
			from sys.availability_replicas ar
			join sys.dm_hadr_availability_replica_states rs
			on rs.replica_id = ar.replica_id and rs.group_id = ar.group_id
			where ar.replica_id = d.replica_id
			) rs
outer apply (select top 1 dm.mirroring_role_desc
			from sys.database_mirroring dm
			where dm.database_id = d.database_id
				and dm.mirroring_role_desc is not null
			) dm
left join sys.dm_database_encryption_keys  ek
	on ek.database_id = d.database_id
left join sys.certificates c
	on c.thumbprint = ek.encryptor_thumbprint
    and c.pvt_key_encryption_type_desc = 'ENCRYPTED_BY_MASTER_KEY'
where 1=1
    and d.state_desc = 'ONLINE' 
    and is_read_only = 0 
    and d.database_id > 4
	$(if($hasCertificateExpired -or $pendingDbCount -gt 0 -or $expiredDbCount -gt 0){'--'})and d.is_encrypted = 0
	and d.source_database_id is null
"@

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Get list of dbs to Encrypt.."
$resultGetAllUserDatabases = @()
$resultGetAllUserDatabases += Invoke-DbaQuery -SqlInstance $conSqlInstanceToEncrypt -Database master `
                                -Query $sqlGetAllUserDatabases

$UserDatabasesToEncrypt = @()
$UserDatabasesToEncrypt += $resultGetAllUserDatabases | Where-Object {($_.role_desc -eq 'PRIMARY') -or ($_.mirroring_role_desc -eq 'PRINCIPAL') -or [String]::IsNullOrEmpty($_.role_desc)}
                                #Select-Object -ExpandProperty database_name

$hadrDatabases = @()
$hadrDatabases += $resultGetAllUserDatabases | Where-Object {([String]::IsNullOrEmpty($_.role_desc) -eq $false) -or ([String]::IsNullOrEmpty($_.mirroring_role_desc) -eq $false)}
                                #Select-Object -ExpandProperty database_name

#$resultGetAllUserDatabases | ogv -Title 'resultGetAllUserDatabases'
#$UserDatabasesToEncrypt | ogv -Title 'UserDatabasesToEncrypt'
#$hadrDatabases | ogv -Title 'hadrDatabases'

if($hadrDatabases.Count -gt 0) 
{
    # Scripts to Restore Certificate/Private Key
    "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Kindly use below query to Restore Certificate/Private Key.."
    $sqlRestoreCertificate = @"
USE [master];

/*  ****************************************************
    For Restore Scenario (AG/Mirroring/LogShipping/Backup-Restore)

    HADR Databases => $( ($hadrDatabases.database_name | % {"'$_'"}) -join ', ' )
*   **************************************************** */


-- Execute "Encrypt-SQLDatabases.ps1" for HADR Partner server also.
create master key encryption by /* Step 1: Unique to Destination Server */
	password = '<<Some Very Strong Password Here. Unique to each server>>';

-- For Restore Scenario (AG/Mirroring/LogShipping/Backup-Restore)
    -- Restore the certificates of each partner on every other partner before proceeding.
create certificate [$certificateName] /* Step 2: Details similar to Source Server */
	from file = '$certificatePath'
	with private key (
		file = '$privateKeyPath',
		decryption by password = '$EncryptionPassword'
	);
"@
    $horizontalLine + "`n" + $sqlRestoreCertificate + "`nGO`n`n" | Out-File -FilePath $scriptOutfile -Append
    $horizontalLine + "`n" + $sqlRestoreCertificate | Write-Host -ForegroundColor Magenta
}

# Loop through each database, and generate encryption key
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Loop through each database & generate Encryption Key.."
foreach($databaseObj in $UserDatabasesToEncrypt)
{
    $is_db_encrypted = $false
    [int]$certificate_expiry_days = 0
    $database = $databaseObj.database_name

    #Write-Debug "Inside loop"

    "`t$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Checking [$database] database.."

    # values which may not be present all the time
    if($databaseObj.is_encrypted) {
        $certificate_expiry_days = $databaseObj.certificate_expiry_days
        $is_db_encrypted = $databaseObj.is_encrypted
    }
    
    # If not encrypted, then create DEK
    if(-not $is_db_encrypted)
    { 
        $sqlCreateOrAlterEncryptionKey = @"
declare @sql nvarchar(max);
declare @thumbprint varbinary(64);

use [master];
-- Get certificate thumbprint
select @thumbprint = c.thumbprint from sys.certificates c 
	where issuer_name = '$certificateSubject' and name = '$certificateName';

use [$database];
-- Create encryption key
if not exists (select * from sys.dm_database_encryption_keys dek where dek.database_id = DB_ID()
					and dek.encryptor_type = 'CERTIFICATE' and dek.key_length = 128 
					and dek.encryptor_thumbprint = @thumbprint )
begin
	set @sql = 'use '+quotename(DB_NAME())+'; '
                +char(9)+'create database encryption key with algorithm = aes_128 '
	            +char(9)+char(9)+'encryption by server certificate [$certificateName];';
	exec (@sql);
    print 'Encryption Key created on [$database].'
end
else
	print 'Database Encryption key exists';
"@
        $sqlCreateOrAlterEncryptionKey + "`nGO`n`n" | Out-File -FilePath $scriptOutfile -Append
        if($DryRun) {
            $sqlCreateOrAlterEncryptionKey | Write-Host -ForegroundColor Magenta
        }
        else {
            Invoke-DbaQuery -SqlInstance $conSqlInstanceToEncrypt -Database master -Query $sqlCreateOrAlterEncryptionKey `
                        -MessagesToOutput -EnableException | Write-Host -ForegroundColor Cyan
        }
    }
    else 
    {
        # If encrypted, then alter DEK
        if ($databaseObj.certificate_expiry_days -gt $ExpiryDaysThreshold) {
            $sqlCreateOrAlterEncryptionKey = "print 'Database [$database] is already encrypted with valid certificate.'";
        }
        else {
            $sqlCreateOrAlterEncryptionKey = @"
use [$database];

-- Alter encryption key
declare @sql nvarchar(max);
set @sql = 'use '+quotename(DB_NAME())+'; '
            +char(9)+'alter database encryption key '
	        +char(9)+char(9)+'encryption by server certificate [$certificateName];';
exec (@sql);
print 'Encryption Key certificate updated on [$database].'
"@
        }
    
        "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Working on [$database].."
        $sqlCreateOrAlterEncryptionKey + "`nGO`n`n" | Out-File -FilePath $scriptOutfile -Append
        if($DryRun) {
            $sqlCreateOrAlterEncryptionKey | Write-Host -ForegroundColor Magenta
        }
        else {
            Invoke-DbaQuery -SqlInstance $conSqlInstanceToEncrypt -Database master -Query $sqlCreateOrAlterEncryptionKey `
                        -MessagesToOutput | Write-Host -ForegroundColor Cyan
        }
    }
}

# Loop through each database, and Encrypt it
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Loop through each database to Encrypt.."
foreach($databaseObj in $UserDatabasesToEncrypt)
{
    $is_db_encrypted = $false
    [int]$certificate_expiry_days = 0
    $database = $databaseObj.database_name

    # values which may not be present all the time
    if($databaseObj.is_encrypted) {
        $certificate_expiry_days = $databaseObj.certificate_expiry_days
        $is_db_encrypted = $databaseObj.is_encrypted
    }

    if($is_db_encrypted){
        "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Database [$database] is already encrypted."
    }
    else
    {
        $sqlEncryptDatabase = @"
-- Enable Encryption
use [master]; alter database [$database] set encryption on;
"@
    
        "$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Encrypting [$database].."
        $sqlEncryptDatabase + "`nGO`n" | Out-File -FilePath $scriptOutfile -Append
        if($DryRun) {
            $sqlEncryptDatabase | Write-Host -ForegroundColor Magenta
        }
        else {
            Invoke-DbaQuery -SqlInstance $conSqlInstanceToEncrypt -Database master -Query $sqlEncryptDatabase `
                        -MessagesToOutput | Write-Host -ForegroundColor Cyan
        }
    }
}


# Save Encryption Details on [CredentialManagerServer]
$sqlSaveEncryptionDetails = @"
-- Save Encryption Details of [$SqlInstanceToEncrypt]
-- Execute below on [$CredentialManagerServer].[$CredentialManagerDatabase]
if not exists (select * from dbo.tde_implementation_details where srv_name = '$SqlInstanceToEncrypt' and server_name = '$serverName' and server_host_name = '$serverHostName' and certificate_name = '$certificateName')
begin
	insert dbo.tde_implementation_details
    ( [srv_name], [at_server_name], [server_name], [domain], [server_host_name], [encrypted_databases], [total_database_count], [encryption_start_time], [encryption_end_time], [local_backup_directory], [remote_backup_directory], [certificate_name], [certificate_subject], [encryption_password], [certificate_file_path], [master_key_path], [private_key_path], [files_copied_to_remote] )
    select	[srv_name] ='$SqlInstanceToEncrypt', 
		    [at_server_name] = '$atServerName', 
		    [server_name] = '$serverName', 
		    [domain] = '$domain', 
		    [server_host_name] = '$serverHostName', 
		    [encrypted_databases] = $($UserDatabasesToEncrypt.Count), 
		    [total_database_count] = $($UserDatabasesToEncrypt.Count), 
		    [encryption_start_time] = SYSDATETIME(), 
		    [encryption_end_time] = null, 
		    [local_backup_directory] = '$backupDirectory', 
		    [remote_backup_directory] = '$RemoteBackupDirectory', 
		    [certificate_name] = '$certificateName', 
		    [certificate_subject] = '$certificateSubject', 
		    [encryption_password] = null, 
		    [certificate_file_path] = '$certificatePath', 
		    [master_key_path] = '$masterKeyPath', 
		    [private_key_path] = '$privateKeyPath', 
		    [files_copied_to_remote] = 0;
    
    print 'TDE Entry added for [$SqlInstanceToEncrypt].'
end
else
    print 'TDE Entry already exists for [$SqlInstanceToEncrypt].'
"@

"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Save encryption details of [$SqlInstanceToEncrypt] on [$CredentialManagerServer].[$CredentialManagerDatabase].[dbo].[tde_implementation_details]."
$horizontalLine + "`n" + $sqlSaveEncryptionDetails + "`nGO`n" | Out-File -FilePath $scriptOutfile -Append
$sqlSaveEncryptionDetails | Write-Host -ForegroundColor Magenta

Invoke-DbaQuery -SqlInstance $conCredentialManagerServer -Database $CredentialManagerDatabase -Query $sqlSaveEncryptionDetails `
                -MessagesToOutput | Write-Host -ForegroundColor Cyan



# Scripts to Check Encryption Status
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Kindly use below query to check Encryption Status.."
$sqlCheckEncryptionStatus = @"
USE [master];
-- Check Encryption Status
SELECT  --[sql_instance] = @@servername,
        [database_name] = d.name, encryption_state_desc, percent_complete, --encryptor_thumbprint,
		[key_algorithm] = ek.key_algorithm + '_'+ convert(varchar,ek.key_length), 
		[certificate_name] = c.name, [certificate_expiry_date] = c.expiry_date, 
		[certificate_expiry_days] = case when c.expiry_date <= getdate() then 0 else datediff(day,getdate(),c.expiry_date) end,
		[certificate_subject] = c.subject,
		[certificate_start_date] = c.start_date,  c.pvt_key_last_backup_date,
		[encryption_key_create_date] = regenerate_date --encryption_scan_state_desc
FROM sys.databases d
left join sys.dm_database_encryption_keys  ek
	on ek.database_id = d.database_id
left join sys.certificates c
	on c.thumbprint = ek.encryptor_thumbprint
    and c.pvt_key_encryption_type_desc = 'ENCRYPTED_BY_MASTER_KEY'
WHERE 1=1
and d.state_desc = 'ONLINE' 
and is_read_only = 0 
and d.database_id > 4
and d.source_database_id is null
"@
$horizontalLine + "`n" + $sqlCheckEncryptionStatus + "`nGO`n" | Out-File -FilePath $scriptOutfile -Append
$horizontalLine + "`n" + $sqlCheckEncryptionStatus | Write-Host -ForegroundColor Magenta


# Scripts to Restore Certificate/Private Key
"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Kindly use below query to Restore Certificate/Private Key.."
$sqlRestoreCertificate = @"
USE [master];
-- For Restore Scenario (AG/Mirroring/LogShipping/Backup-Restore)
create master key encryption by /* Step 1: Unique to Destination Server */
	password = '<<Some Very Strong Password Here. Unique to each server>>';

-- For Restore Scenario (AG/Mirroring/LogShipping/Backup-Restore)
create certificate [$certificateName] /* Step 2: Details similar to Source Server */
	from file = '$certificatePath'
	with private key (
		file = '$privateKeyPath',
		decryption by password = '$EncryptionPassword'
	);
"@
$horizontalLine + "`n" + $sqlRestoreCertificate + "`nGO`n" | Out-File -FilePath $scriptOutfile -Append
$horizontalLine + "`n" + $sqlRestoreCertificate | Write-Host -ForegroundColor Magenta


"$(Get-Date -Format yyyyMMMdd_HHmm) {0,-10} {1}" -f 'INFO:', "Opening scriptout file '$scriptOutfile'.."
notepad $scriptOutfile
#>

<#
Import-Module dbatools

# $allServerLoginCredential = Get-Credential -UserName 'sa' -Message 'All Server Login Credential'
$Server2Encrypt = 'AgHost-1A'

cls
E:\Github\SQLMonitor\Work-TDE\Encrypt-SQLDatabases.ps1 `
        -SqlInstanceToEncrypt $Server2Encrypt `
        -SqlCredential $allServerLoginCredential `
        -ScriptOut $False `
        #-EncryptionPassword 'YourMasterKeyPasswordHere' #-Debug
#>