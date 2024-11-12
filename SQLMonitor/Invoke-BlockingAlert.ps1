[CmdletBinding()]
Param (
    [Parameter(Mandatory=$false)]
    [string]$InventoryServer = 'SqlMonitor',
    [Parameter(Mandatory=$false)]
    [string]$InventoryDatabase = 'DBA',
    [Parameter(Mandatory=$false)]
    [string]$SlackAlertTitle = 'Blocking Alert',
    [Parameter(Mandatory=$false)]
    [string]$SqlMonitorDashboardLink = 'https://sqlmonitor:3000/d/distributed_live_dashboard_all_servers/monitoring-live-all-servers?orgId=1&refresh=1m',
    [Parameter(Mandatory=$false)]
    [string]$SlackPreText = "Blocking has been detected. Kindly check on All Server Dashboard!",
    [Parameter(Mandatory=$false)]
    $BlockedCountsThreshold = 30,
    [Parameter(Mandatory=$false)]
    $BlockedDurationMaxSecondsThreshold = 300,
    [Parameter(Mandatory=$false)]
    $ConnectionCountThreshold = 300,
    [Parameter(Mandatory=$false)]
    [string]$SlackURI = "https://hooks.slack.com/services/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bx1K"
)

Import-Module dbatools,psslack,PSScriptTools;

$blockingQuery = @"
declare @blocked_counts_threshold int = $BlockedCountsThreshold;
declare @blocked_duration_max_seconds_threshold bigint = $BlockedDurationMaxSecondsThreshold;
declare @connection_count_threshold int = $ConnectionCountThreshold;

declare @sql nvarchar(max);
declare @params nvarchar(max);

set @params = N'@blocked_counts_threshold int, @blocked_duration_max_seconds_threshold bigint, @connection_count_threshold int';

set quoted_identifier off;
set @sql = "
;with t_cte as (
    select  srv_name, blocked_counts, blocked_duration_max_seconds, connection_count
    from dbo.vw_all_server_info
)
select  *
from t_cte cte
where 1=1
and (   (   blocked_counts >= @blocked_counts_threshold
            and blocked_duration_max_seconds >= @blocked_duration_max_seconds_threshold
        )
    or  (   connection_count >= @connection_count_threshold 
            and blocked_duration_max_seconds >= @blocked_duration_max_seconds_threshold/2
            and blocked_counts >= @blocked_counts_threshold/2
        )
)
";
set quoted_identifier off;
--print @sql
exec dbo.sp_executesql @sql, @params, @blocked_counts_threshold, @blocked_duration_max_seconds_threshold, @connection_count_threshold;
"@
$blockingResult = @()
$blockingResult += Invoke-DbaQuery -SqlInstance $InventoryServer -Database $InventoryDatabase -Query $blockingQuery
if($blockingResult.Count -gt 0) {
    $slackText = "Some Blocking Info here"
    #$slackText = $blockingResult | Select-Object srv_name,blocked_counts,blocked_duration_max_seconds,connection_count | ConvertTo-SdtMarkdownTable | Out-String
    $slackText = $blockingResult | Select-Object srv_name,blocked_counts,blocked_duration_max_seconds,connection_count | ConvertTo-Markdown | Out-String
    New-SlackMessageAttachment -Color $([System.Drawing.Color]::red) `
                               -Title $SlackAlertTitle `
                               -TitleLink $SqlMonitorDashboardLink `
                               -Text $slackText `
                               -Pretext $SlackPreText `
                               -AuthorName 'SQLMonitor' `
                               -Fallback 'Something is wrong' |
    New-SlackMessage -IconEmoji ':bomb:' | Send-SlackMessage -Uri $SlackURI
}
else {
    "No blocking detected valid for alerting."
}


