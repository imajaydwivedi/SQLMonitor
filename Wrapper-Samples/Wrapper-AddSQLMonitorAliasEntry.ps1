<#
    Purpose: Run sql script on multiple servers, and process result
#>
#$personal = Get-Credential -UserName 'adwivedi' -Message 'Credential Manager Server SQL Login'

cls
import-module dbatools

# Parameters
$AliasSqlInstance = '192.168.1.12'
#$SourceSqlInstance = ''
$params = @{
    AliasSqlInstance = $AliasSqlInstance
    SourceSqlInstance = $SourceSqlInstance
    InventoryServer = 'OfficeInventory'
    InventoryDatabase = 'DBA_Admin'
    SqlCredential = $personal
    #DropCreateLinkedServer = $true
    #ReturnInlineErrorMessage = $true
    Move2NextStepOnFailure = $true
}

D:\GitHub-Personal\SQLMonitor\SQLMonitor\Add-SQLMonitorAliasEntry.ps1 @params #-Debug

