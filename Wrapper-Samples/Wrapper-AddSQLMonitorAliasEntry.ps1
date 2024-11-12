<#
    Purpose: Run sql script on multiple servers, and process result
#>
#$personal = Get-Credential -UserName 'adwivedi' -Message 'Credential Manager Server SQL Login'

cls
import-module dbatools

# Parameters
$AliasSqlInstance = '192.168.100.109'
#$SourceSqlInstance = ''
$params = @{
    AliasSqlInstance = $AliasSqlInstance
    SourceSqlInstance = $SourceSqlInstance
    InventoryServer = 'SQLMonitor'
    InventoryDatabase = 'DBA'
    SqlCredential = $personal
    #DropCreateLinkedServer = $true
    #ReturnInlineErrorMessage = $true
    Move2NextStepOnFailure = $true
}


E:\GitHub\SQLMonitor\SQLMonitor\Add-SQLMonitorAliasEntry.ps1 @params #-Debug

