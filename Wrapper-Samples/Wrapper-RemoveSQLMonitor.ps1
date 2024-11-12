#$DomainCredential = Get-Credential -UserName 'Lab\SQLServices' -Message 'AD Account'
#$saAdmin = Get-Credential -UserName 'sa' -Message 'sa'
#$localAdmin = Get-Credential -UserName 'Administrator' -Message 'Local Admin'

cls
Import-Module dbatools;
$params = @{
    SqlInstanceToBaseline = 'Experiment'
    #DbaDatabase = 'DBA'
    #HostName = 'Experiment'
    InventoryServer = 'SQLMonitor'
    InventoryDatabase = 'DBA'
    #RemoteSQLMonitorPath = 'C:\SQLMonitor'
    #SqlCredential = $saAdmin
    #WindowsCredential = $localAdmin
    #SkipSteps = @("43__RemovePerfmonFilesFromDisk")
    #StartAtStep = '47__DropLogin_Grafana'
    #StopAtStep = '11__RemoveJob_RunBlitzIndex'
    #SqlInstanceForTsqlJobs = 'Experiment\SQL2019'
    #SqlInstanceAsDataDestination = 'Experiment\SQL2019'
    #SqlInstanceForPowershellJobs = 'Experiment\SQL2019'
    #SkipDropTable = $false
    #SkipDropTablesForInventory = $true
    #SkipRemoveJob = $true
    #SkipDropProc = $true
    #SkipDropView = $true
    #SkipAllInventorySteps = $true
    #ConfirmValidationOfMultiInstance = $true
    DryRun = $false
}

#$preSQL = "EXEC dbo.usp_check_sql_agent_jobs @default_mail_recipient = 'sqlagentservice@gmail.com', @drop_recreate = 1"
#$postSQL = Get-Content "D:\GitHub-Personal\SQLMonitor\DDLs\Update-SQLAgentJobsThreshold.sql"
#D:\GitHub\SQLMonitor\SQLMonitor\Remove-SQLMonitor.ps1 @Params #-Debug -PreQuery $preSQL -PostQuery $postSQL
D:\GitHub\SQLMonitor\SQLMonitor\Remove-SQLMonitor.ps1 @Params


#Get-DbaDbMailProfile -SqlInstance '192.168.56.31' -SqlCredential $personalCredential
#Copy-DbaDbMail -Source '192.168.56.15' -Destination '192.168.56.31' -SourceSqlCredential $personalCredential -DestinationSqlCredential $personalCredential # Lab
#New-DbaCredential -SqlInstance 'xy' -Identity $LabCredential.UserName -SecurePassword $LabCredential.Password -Force # -SqlCredential $SqlCredential -EnableException
#New-DbaAgentProxy -SqlInstance 'xy' -Name $LabCredential.UserName -ProxyCredential $LabCredential.UserName -SubSystem PowerShell,CmdExec
<#

Enable-PSRemoting -Force # run on remote machine
Set-Item WSMAN:\Localhost\Client\TrustedHosts -Value * -Force # run on local machine
Set-Item WSMAN:\Localhost\Client\TrustedHosts -Value 192.168.56.15 -Force
#Set-NetConnectionProfile -NetworkCategory Private # Execute this only if above command fails

Enter-PSSession -ComputerName '192.168.56.31' -Credential $localAdmin -Authentication Negotiate
Test-WSMan '192.168.56.31' -Credential $localAdmin -Authentication Negotiate


#>
